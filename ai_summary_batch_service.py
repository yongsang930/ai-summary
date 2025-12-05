import json
import time
from typing import Optional, Tuple
import psycopg2
import logging
import google.generativeai as genai


class AISummaryBatchService:
    def __init__(self, db_config: dict, gemini_api_key: str):
        self.db_config = db_config
        self.logger = logging.getLogger("ai-summary-batch")
        genai.configure(api_key=gemini_api_key)
        self.logger.info(f"google-generativeai version = {genai.__version__}")
        self.model = genai.GenerativeModel("gemini-flash-latest")

    def _get_conn(self):
        return psycopg2.connect(**self.db_config)

    def _gemini_summarize(self, content: str, title: Optional[str] = None, max_retries: int = 3) -> Optional[str]:
        """Gemini API를 사용하여 콘텐츠를 요약합니다. 429 에러 발생 시 재시도합니다. 실패 시 None을 반환합니다."""
        # 제목이 있으면 프롬프트에 포함
        prompt_content = content
        if title:
            prompt_content = f"제목: {title}\n\n내용: {content}"

        prompt = f"""당신은 기술 블로그 포스트를 간결하고 명확하게 요약하는 전문가입니다. 핵심 내용을 2-3문장으로 요약해주세요.

다음 글을 요약해주세요:

{prompt_content}"""

        for attempt in range(max_retries):
            try:
                # API 요청 전 6초 대기 (첫 요청이 아닌 경우)
                if attempt > 0:
                    self.logger.info(f"요약 재시도 {attempt}/{max_retries - 1} - 6초 대기 중...")
                    time.sleep(6)
                
                response = self.model.generate_content(prompt)
                
                # 성공한 경우 다음 요청을 위해 6초 대기
                summary = response.text.strip()
                time.sleep(6)
                return summary
                
            except Exception as e:
                error_str = str(e)
                
                # 429 에러 (Quota exceeded)인 경우 재시도
                if "429" in error_str or "quota" in error_str.lower() or "rate limit" in error_str.lower():
                    if attempt < max_retries - 1:
                        # 에러 메시지에서 retry_delay 추출 시도
                        retry_delay = 60  # 기본값 60초
                        if "retry in" in error_str.lower():
                            try:
                                import re
                                match = re.search(r'retry in ([\d.]+)s', error_str.lower())
                                if match:
                                    retry_delay = int(float(match.group(1))) + 1
                            except:
                                pass
                        
                        self.logger.warning(f"429 에러 발생 (Quota exceeded). {retry_delay}초 후 재시도 {attempt + 1}/{max_retries}...")
                        time.sleep(retry_delay)
                        continue
                    else:
                        self.logger.error(f"Gemini 요약 생성 실패 (최대 재시도 횟수 초과): {error_str[:500]}")
                        return None
                else:
                    # 429가 아닌 다른 에러는 즉시 반환
                    self.logger.error(f"Gemini 요약 생성 실패: {error_str[:500]}")
                    return None
        
        return None

    def run(self) -> None:
        """summary가 NULL인 포스트들을 찾아서 AI 요약을 생성하고 업데이트합니다."""
        start_time = time.time()
        self.logger.info("AI 요약 배치 시작")

        conn = self._get_conn()
        cur = conn.cursor()
        
        try:
            # summary가 NULL이고 content가 비어있지 않은 포스트만 조회
            cur.execute(
                """
                SELECT post_id, content, title
                FROM posts
                WHERE summary IS NULL
                  AND content IS NOT NULL
                  AND content != ''
                  AND TRIM(content) != ''
                ORDER BY post_id ASC
                """
            )
            rows = cur.fetchall()
            total_count = len(rows)
            
            if total_count == 0:
                self.logger.info("요약할 포스트가 없습니다.")
                return

            self.logger.info(f"요약 대상 포스트 {total_count}개 발견")

            success_count = 0
            fail_count = 0

            for idx, (post_id, content, title) in enumerate(rows, 1):
                try:
                    # content가 None이거나 빈 문자열인 경우 건너뛰기 (이중 체크)
                    if not content or not content.strip():
                        self.logger.warning(f"[{idx}/{total_count}] post_id={post_id}: content가 비어있어 건너뜀")
                        continue

                    # summary가 이미 있는지 확인 (이중 체크)
                    cur.execute("SELECT summary FROM posts WHERE post_id = %s", (post_id,))
                    existing_summary = cur.fetchone()
                    if existing_summary and existing_summary[0] is not None:
                        self.logger.info(f"[{idx}/{total_count}] post_id={post_id}: summary가 이미 존재하여 건너뜀")
                        continue

                    self.logger.info(f"[{idx}/{total_count}] post_id={post_id} 요약 생성 중...")
                    
                    # Gemini로 요약 생성
                    summary = self._gemini_summarize(content, title)
                    
                    # 요약 생성 실패 시 건너뛰기
                    if summary is None:
                        fail_count += 1
                        self.logger.warning(f"[{idx}/{total_count}] post_id={post_id}: 요약 생성 실패로 건너뜀")
                        continue
                    
                    # DB 업데이트
                    cur.execute(
                        "UPDATE posts SET summary = %s WHERE post_id = %s",
                        (summary, post_id)
                    )
                    conn.commit()
                    
                    success_count += 1
                    self.logger.debug(f"  └─ 요약 완료: {summary[:100]}...")
                    
                except Exception as e:
                    fail_count += 1
                    conn.rollback()
                    error_msg = str(e)[:500]
                    self.logger.error(f"[{idx}/{total_count}] post_id={post_id} 요약 실패: {error_msg}")
                    # 예외가 발생해도 다음 포스트로 계속 진행
                    continue

            elapsed = time.time() - start_time
            self.logger.info(f"AI 요약 배치 완료 - 성공: {success_count}, 실패: {fail_count}, 소요시간: {elapsed:.2f}초")

            # 배치 로그 기록
            self._log_batch("SUCCESS", success_count, fail_count, total_count, None)

        except Exception as e:
            error_message = str(e)[:1000]
            self.logger.error(f"AI 요약 배치 실행 중 오류 발생: {error_message}")
            self._log_batch("FAILED", 0, 0, 0, error_message)
            raise
        finally:
            cur.close()
            conn.close()

    def _log_batch(self, status: str, success_count: int, fail_count: int, total_count: int, error_message: Optional[str]) -> None:
        """batch_logs 테이블에 배치 실행 로그를 기록합니다."""
        conn = self._get_conn()
        cur = conn.cursor()
        try:
            detail = {
                "success_count": success_count,
                "fail_count": fail_count,
                "total_count": total_count,
            }
            
            log_level = "ERROR" if status == "FAILED" else "INFO"
            
            cur.execute(
                """
                INSERT INTO batch_logs (job_type, log_level, status, affected_count, detail, error_message)
                VALUES (%s, %s, %s, %s, %s, %s)
                """,
                ("AI_SUMMARY", log_level, status, success_count, json.dumps(detail), error_message),
            )
            conn.commit()
        finally:
            cur.close()
            conn.close()

