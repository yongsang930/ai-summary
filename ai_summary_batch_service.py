import json
import time
from typing import Optional, Tuple
import psycopg2
import logging
import google.generativeai as genai
import requests
from readability import Document
from bs4 import BeautifulSoup


class AISummaryBatchService:
    def __init__(self, db_config: dict, gemini_api_key: str):
        self.db_config = db_config
        self.logger = logging.getLogger("ai-summary-batch")
        genai.configure(api_key=gemini_api_key)
        self.logger.info(f"google-generativeai version = {genai.__version__}")
        self.model = genai.GenerativeModel("gemini-flash-latest")

    def _get_conn(self):
        return psycopg2.connect(**self.db_config)

    def _fetch_url_content(self, url: str) -> Tuple[Optional[str], Optional[int]]:
        """URL에서 페이지 본문 내용을 가져옵니다. readability-lxml을 사용하여 깔끔하게 추출합니다.
        
        Returns:
            Tuple[Optional[str], Optional[int]]: 
                - (content, None): 성공
                - (None, None): 실패 (404가 아닌 에러)
                - (None, 404): 404 에러 발생
        """
        try:
            headers = {
                'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36'
            }
            response = requests.get(url, headers=headers, timeout=30)
            response.raise_for_status()
            
            # readability-lxml을 사용하여 본문 추출
            doc = Document(response.content)
            content_html = doc.summary()
            
            # HTML에서 텍스트만 추출
            soup = BeautifulSoup(content_html, 'html.parser')
            content = soup.get_text(separator=' ', strip=True)
            
            if content:
                # 공백 정리 및 길이 제한 (너무 긴 경우)
                content = ' '.join(content.split())
                if len(content) > 10000:
                    content = content[:10000] + "..."
                return (content, None)
            
            return (None, None)
        except requests.exceptions.HTTPError as e:
            if e.response and e.response.status_code == 404:
                self.logger.warning(f"URL 404 에러 ({url}): 페이지를 찾을 수 없습니다.")
                return (None, 404)
            else:
                self.logger.error(f"URL HTTP 에러 ({url}): {str(e)[:200]}")
                return (None, None)
        except Exception as e:
            self.logger.error(f"URL 내용 가져오기 실패 ({url}): {str(e)[:200]}")
            return (None, None)

    def _gemini_summarize(self, content: str, title: Optional[str] = None) -> Tuple[Optional[str], Optional[float]]:
        """Gemini API를 사용하여 콘텐츠를 요약합니다.
        
        Returns:
            Tuple[Optional[str], Optional[float]]: 
                - (summary, None): 성공
                - (None, None): 실패
                - (None, retry_delay): 429 에러로 재시도 필요 (retry_delay 초 후 재시도)
        """
        # 제목이 있으면 프롬프트에 포함
        prompt_content = content
        if title:
            prompt_content = f"제목: {title}\n\n내용: {content}"

        prompt = f"""당신은 IT 전문가와 개발자들을 대상으로 하는 기술 블로그 요약 전문가입니다.

요약 규칙:
- 2~3개의 짧은 문장으로 요약
- 개발자 관점에서 기술적 핵심 내용에 집중
- 사용된 기술 스택, 아키텍처, 구현 방법 등 실무적 정보 강조
- 목적, 핵심 아이디어, 주요 결과를 개발자가 빠르게 파악할 수 있도록 정리
- 불필요하게 길거나 난해한 표현 금지
- 한 문장은 25~30자 이내로 자연스럽게
- 마침표로 문장을 명확히 구분
- IT 전문가와 개발자들이 실무에 적용 가능한 정보를 빠르게 이해할 수 있도록 작성

아래 글을 개발자 관점에서 요약해주세요:

{prompt_content}"""

        try:
            response = self.model.generate_content(prompt)
            
            # 성공한 경우
            summary = response.text.strip()
            return (summary, None)
            
        except Exception as e:
            error_str = str(e)
            
            # 429 에러 (Quota exceeded)인 경우 재시도 지시 반환
            if "429" in error_str or "quota" in error_str.lower() or "rate limit" in error_str.lower():
                # 에러 메시지에서 retry_delay 추출 시도
                retry_delay = 60  # 기본값 60초
                quota_metric = None
                quota_limit = None
                
                if "retry in" in error_str.lower():
                    try:
                        import re
                        match = re.search(r'retry in ([\d.]+)s', error_str.lower())
                        if match:
                            retry_delay = float(match.group(1)) + 1
                    except:
                        pass
                
                # 할당량 정보 추출
                try:
                    import re
                    metric_match = re.search(r'quota_metric[:\s]+"([^"]+)"', error_str)
                    if metric_match:
                        quota_metric = metric_match.group(1)
                    
                    limit_match = re.search(r'quota_value[:\s]+(\d+)', error_str)
                    if limit_match:
                        quota_limit = limit_match.group(1)
                except:
                    pass
                
                # 필요한 정보만 로그 기록
                log_parts = [f"429 에러 발생 (Quota exceeded), 재시도 대기: {retry_delay:.1f}초"]
                if quota_metric:
                    log_parts.append(f"할당량 메트릭: {quota_metric}")
                if quota_limit:
                    log_parts.append(f"할당량 제한: {quota_limit}")
                
                self.logger.warning(" - ".join(log_parts))
                return (None, retry_delay)
            else:
                # 429가 아닌 다른 에러는 즉시 실패 반환
                self.logger.error(f"Gemini 요약 생성 실패: {error_str[:500]}")
                return (None, None)

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
                    
                    # Gemini로 요약 생성 (재시도 로직 포함)
                    summary, retry_delay = self._gemini_summarize(content, title)
                    
                    # 429 에러인 경우에만 120초 대기 후 1회 재시도
                    if summary is None and retry_delay is not None:
                        self.logger.info(f"[{idx}/{total_count}] post_id={post_id}: 429 에러 발생, 120초 후 1회 재시도...")
                        time.sleep(120)
                        summary, retry_delay_after_retry = self._gemini_summarize(content, title)
                        
                        # 재시도 후에도 429 에러가 발생하면 할당량 제한으로 판단하고 스크립트 종료
                        if summary is None and retry_delay_after_retry is not None:
                            self.logger.error(f"[{idx}/{total_count}] post_id={post_id}: 재시도 후에도 429 에러 발생. 할당량 제한으로 판단하여 스크립트를 종료합니다.")
                            self.logger.info(f"처리 완료된 포스트: {success_count}건, 실패: {fail_count}건")
                            return
                        
                        if summary is None:
                            self.logger.warning(f"[{idx}/{total_count}] post_id={post_id}: 재시도 후에도 실패, 다음 실행으로 넘어감")
                    
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
                    self.logger.debug(f"요약 완료: {summary[:100]}...")
                    
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

