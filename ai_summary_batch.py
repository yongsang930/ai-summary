import os
import logging
from ai_summary_batch_service import AISummaryBatchService
from config import get_db_config, setup_logging

# .env 파일 지원 (있는 경우)
try:
    from dotenv import load_dotenv
    load_dotenv()
except ImportError:
    pass  # python-dotenv가 없어도 환경변수는 정상 작동

setup_logging()
logger = logging.getLogger("ai-summary-batch")

DB_CONFIG = get_db_config()

# Gemini API 키는 환경변수에서 가져옵니다
GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY") or os.getenv("GEMINI_API_KEY")
if not GEMINI_API_KEY:
    raise ValueError("GEMINI_API_KEY 환경변수가 설정되지 않았습니다.")

if __name__ == "__main__":
    logger.info("AI 요약 배치 시작")
    service = AISummaryBatchService(DB_CONFIG, GEMINI_API_KEY)
    service.run()
    logger.info("AI 요약 배치 완료")

