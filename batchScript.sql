-- =================================================================
-- 1. TABLE CREATION
-- =================================================================

-- USERS Table
CREATE TABLE users (
	user_id int8 GENERATED ALWAYS AS IDENTITY( INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 START 1 CACHE 1 NO CYCLE) NOT NULL,
	login_type varchar(20) NOT NULL,
	social_id varchar(255) NULL,
	email varchar(255) NULL,
	nickname varchar(50) NULL,
	created_at timestamp DEFAULT now() NOT NULL,
	updated_at timestamp DEFAULT now() NOT NULL,
	CONSTRAINT users_email_key UNIQUE (email),
	CONSTRAINT users_pkey PRIMARY KEY (user_id),
	CONSTRAINT users_social_id_key UNIQUE (social_id)
);

-- KEYWORDS Table
CREATE TABLE keywords (
	keyword_id int8 GENERATED ALWAYS AS IDENTITY( INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 START 1 CACHE 1 NO CYCLE) NOT NULL,
	en_name varchar(50) NOT NULL,
	is_active bool DEFAULT true NOT NULL,
	created_at timestamp DEFAULT now() NOT NULL,
	deleted_at timestamp NULL,
	ko_name varchar(50) NOT NULL,
	CONSTRAINT keywords_name_key UNIQUE (en_name),
	CONSTRAINT keywords_pkey PRIMARY KEY (keyword_id),
	CONSTRAINT unique_ko_name_en_name UNIQUE (ko_name, en_name)
);

-- RSS_FEEDS Table
CREATE TABLE rss_feeds (
	feed_id int8 GENERATED ALWAYS AS IDENTITY( INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 START 1 CACHE 1 NO CYCLE) NOT NULL,
	region varchar(20) NOT NULL,
	feed_url varchar(2048) NOT NULL,
	is_active bool DEFAULT true NOT NULL,
	last_crawled_at timestamp NULL,
	created_at timestamp DEFAULT now() NOT NULL,
	CONSTRAINT rss_feeds_feed_url_key UNIQUE (feed_url),
	CONSTRAINT rss_feeds_pkey PRIMARY KEY (feed_id),
	CONSTRAINT rss_feeds_region_check CHECK (((region)::text = ANY ((ARRAY['DOMESTIC'::character varying, 'GLOBAL'::character varying])::text[])))
);

-- POSTS Table
CREATE TABLE posts (
	post_id int8 GENERATED ALWAYS AS IDENTITY( INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 START 1 CACHE 1 NO CYCLE) NOT NULL,
	title varchar(255) NOT NULL,
	link varchar(2048) NOT NULL,
	link_hash varchar(64) NOT NULL,
	summary text NULL,
	region varchar(20) NOT NULL,
	published_at timestamp NOT NULL,
	created_at timestamp DEFAULT now() NOT NULL,
	CONSTRAINT posts_pkey PRIMARY KEY (post_id),
	CONSTRAINT posts_region_check CHECK (((region)::text = ANY ((ARRAY['DOMESTIC'::character varying, 'GLOBAL'::character varying])::text[])))
);

-- USER_PREFERRED_KEYWORDS Table
CREATE TABLE user_preferred_keywords (
	user_id int8 NOT NULL,
	keyword_id int8 NOT NULL,
	CONSTRAINT user_preferred_keywords_pkey PRIMARY KEY (user_id, keyword_id)
);

-- POST_KEYWORDS Table
CREATE TABLE post_keywords (
	post_id int8 NOT NULL,
	keyword_id int8 NOT NULL,
	CONSTRAINT post_keywords_pkey PRIMARY KEY (post_id, keyword_id)
);

CREATE TABLE batch_logs (
    log_id BIGSERIAL PRIMARY KEY,                    -- 배치 로그 ID (PK)
    job_type VARCHAR(30) NOT NULL,                   -- 배치 작업 종류 (CRAWLER, CLEANER, SUMMARY, LINK_CHECK 등)
    log_level VARCHAR(20) NOT NULL,                  -- 로그 레벨 (INFO, WARN, ERROR 등)
    status VARCHAR(20) NOT NULL,                     -- SUCCESS / FAILED
    affected_count INT DEFAULT 0 NOT NULL,           -- 처리된 데이터 개수
    detail JSONB NULL,                               -- 배치 상세 정보 (feed_id, feed_url, context 등)
    error_message TEXT NULL,                         -- 실패 시 에러 메시지
    executed_at TIMESTAMP DEFAULT now() NOT NULL     -- 배치 실행 시각
);

ALTER TABLE batch_logs
ADD CONSTRAINT batch_logs_status_check
CHECK (status IN ('SUCCESS', 'FAILED'));

ALTER TABLE batch_logs
ADD CONSTRAINT batch_logs_log_level_check
CHECK (log_level IN ('INFO', 'DEBUG', 'WARN', 'ERROR'));

-- REFRESH_TOKENS Table
CREATE TABLE refresh_tokens (
    token_id BIGSERIAL PRIMARY KEY,             -- 리프레시 토큰 고유 ID
    user_id BIGINT NOT NULL,                    -- 사용자 ID (FK)
    refresh_token TEXT NOT NULL,                -- 실제 리프레시 토큰 문자열
    expired_at TIMESTAMP NOT NULL,              -- 만료 시각
    created_at TIMESTAMP DEFAULT NOW() NOT NULL, -- 생성 시간
    last_used_at TIMESTAMP NULL,                -- 최근 사용 시간(선택)
    CONSTRAINT fk_refresh_tokens_to_users
        FOREIGN KEY (user_id)
        REFERENCES public.users(user_id)
        ON DELETE CASCADE
);


-- =================================================================
-- 2. TABLE & COLUMN COMMENTS
-- =================================================================

-- USERS
COMMENT ON COLUMN users.user_id IS '사용자 고유 ID (PK)';
COMMENT ON COLUMN users.login_type IS '로그인 타입 (LOCAL / SOCIAL 등)';
COMMENT ON COLUMN users.social_id IS '소셜 로그인 고유 식별자';
COMMENT ON COLUMN users.email IS '사용자 이메일';
COMMENT ON COLUMN users.nickname IS '사용자 닉네임';
COMMENT ON COLUMN users.created_at IS '생성 일시';
COMMENT ON COLUMN users.updated_at IS '수정 일시';

-- KEYWORDS
COMMENT ON COLUMN keywords.keyword_id IS '키워드 ID (PK)';
COMMENT ON COLUMN keywords.en_name IS '키워드 영어 이름';
COMMENT ON COLUMN keywords.is_active IS '키워드 활성 여부';
COMMENT ON COLUMN keywords.created_at IS '생성 일시';
COMMENT ON COLUMN keywords.deleted_at IS '키워드 삭제 일시 (Soft Delete)';
COMMENT ON COLUMN keywords.ko_name IS '키워드 한국어 이름';

-- RSS_FEEDS
COMMENT ON COLUMN rss_feeds.feed_id IS 'RSS 피드 ID (PK)';
COMMENT ON COLUMN rss_feeds.region IS '지역 구분 (DOMESTIC / GLOBAL)';
COMMENT ON COLUMN rss_feeds.feed_url IS 'RSS Feed URL';
COMMENT ON COLUMN rss_feeds.is_active IS '피드 활성 여부';
COMMENT ON COLUMN rss_feeds.last_crawled_at IS '마지막 수집 실행 일시';
COMMENT ON COLUMN rss_feeds.created_at IS '생성 일시';

-- POSTS
COMMENT ON COLUMN posts.post_id IS '게시물 ID (PK)';
COMMENT ON COLUMN posts.title IS '게시물 제목';
COMMENT ON COLUMN posts.link IS '원문 링크(URL)';
COMMENT ON COLUMN posts.link_hash IS 'link의 SHA256 해시값 (중복방지용, Application에서 생성)';
COMMENT ON COLUMN posts.summary IS '게시물 요약 (AI 또는 기본 요약)';
COMMENT ON COLUMN posts.region IS '지역 구분 (DOMESTIC / GLOBAL)';
COMMENT ON COLUMN posts.published_at IS '게시물 원문 발행 시각(RSS 제공값)';
COMMENT ON COLUMN posts.created_at IS '저장 일시';

-- USER_PREFERRED_KEYWORDS
COMMENT ON COLUMN user_preferred_keywords.user_id IS '사용자 ID';
COMMENT ON COLUMN user_preferred_keywords.keyword_id IS '키워드 ID';

-- POST_KEYWORDS
COMMENT ON COLUMN post_keywords.post_id IS '게시물 ID';
COMMENT ON COLUMN post_keywords.keyword_id IS '키워드 ID';

-- BATCH_LOGS
COMMENT ON COLUMN batch_logs.log_id IS '배치 로그 ID (PK)';
COMMENT ON COLUMN batch_logs.job_type IS '배치 작업 종류 (예: CRAWLER, CLEANER, SUMMARY, LINK_CHECK)';
COMMENT ON COLUMN batch_logs.log_level IS '로그 레벨 (INFO, WARN, ERROR)';
COMMENT ON COLUMN batch_logs.status IS '배치 작업 상태 (SUCCESS / FAILED)';
COMMENT ON COLUMN batch_logs.affected_count IS '배치 작업에서 처리된 행 개수';
COMMENT ON COLUMN batch_logs.detail IS '배치 상세 정보(JSONB): feed_id, feed_url, context 등 저장';
COMMENT ON COLUMN batch_logs.error_message IS '배치 오류 메시지';
COMMENT ON COLUMN batch_logs.executed_at IS '배치 실행 시각';

-- REFRESH_TOKENS
COMMENT ON TABLE refresh_tokens IS '사용자 리프레시 토큰 관리 테이블';
COMMENT ON COLUMN refresh_tokens.token_id IS '리프레시 토큰 ID (PK)';
COMMENT ON COLUMN refresh_tokens.user_id IS '사용자 ID (FK)';
COMMENT ON COLUMN refresh_tokens.refresh_token IS '리프레시 토큰 문자열';
COMMENT ON COLUMN refresh_tokens.expired_at IS '리프레시 토큰 만료 시각';
COMMENT ON COLUMN refresh_tokens.created_at IS '리프레시 토큰 생성 일시';
COMMENT ON COLUMN refresh_tokens.last_used_at IS '리프레시 토큰 최근 사용 일시';


-- =================================================================
-- 3. INDEX CREATION
-- =================================================================

CREATE INDEX idx_posts_created_at ON public.posts USING btree (created_at);
CREATE INDEX idx_posts_published_at ON public.posts USING btree (published_at);
CREATE INDEX idx_posts_region_published ON public.posts USING btree (region, published_at DESC);

CREATE UNIQUE INDEX uk_posts_link_hash ON public.posts USING btree (link_hash);

CREATE INDEX idx_keywords_deleted_at ON public.keywords USING btree (deleted_at);
CREATE INDEX idx_keywords_is_active ON public.keywords USING btree (is_active);

CREATE INDEX idx_rss_feeds_is_active ON public.rss_feeds USING btree (is_active);

CREATE INDEX idx_post_keywords_post_id ON public.post_keywords USING btree (post_id);

-- BATCH_LOGS 인덱스
CREATE INDEX idx_batch_logs_executed_at ON public.batch_logs USING btree (executed_at DESC);
CREATE INDEX idx_batch_logs_job_type ON public.batch_logs USING btree (job_type);
CREATE INDEX idx_batch_logs_status ON public.batch_logs USING btree (status);
CREATE INDEX idx_batch_logs_log_level ON public.batch_logs USING btree (log_level);
CREATE INDEX idx_batch_logs_detail_feed_id ON public.batch_logs USING btree ((detail->>'feed_id'));


-- =================================================================
-- 4. FOREIGN KEY CONSTRAINTS
-- =================================================================

ALTER TABLE public.user_preferred_keywords ADD CONSTRAINT fk_user_preferred_keywords_to_keywords 
FOREIGN KEY (keyword_id) REFERENCES public.keywords(keyword_id) ON DELETE CASCADE;

ALTER TABLE public.user_preferred_keywords ADD CONSTRAINT fk_user_preferred_keywords_to_users 
FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE CASCADE;

ALTER TABLE public.post_keywords ADD CONSTRAINT fk_post_keywords_to_keywords 
FOREIGN KEY (keyword_id) REFERENCES public.keywords(keyword_id) ON DELETE CASCADE;

ALTER TABLE public.post_keywords ADD CONSTRAINT fk_post_keywords_to_posts 
FOREIGN KEY (post_id) REFERENCES public.posts(post_id) ON DELETE CASCADE;


-- =================================================================
-- 5. TRIGGER FOR AUTO-UPDATING TIMESTAMPS
-- =================================================================

-- 모든 테이블에서 재사용 가능한 공용 함수 생성
CREATE OR REPLACE FUNCTION trigger_set_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- USERS 테이블에 트리거 적용
create trigger set_timestamp_users before
update
    on
    public.users for each row execute function trigger_set_timestamp();


-- =================================================================
-- 6. SAMPLE DATA INSERTION
-- =================================================================

INSERT INTO keywords (ko_name, en_name) VALUES
('에이전트 AI', 'AI Agent'),
('생성형 AI', 'Generative AI'),
('LLM', 'LLM'),
('온디바이스 AI', 'On-device AI'),
('머신러닝옵스', 'MLOps'),
('컴퓨터 비전', 'Computer Vision'),
('자연어 처리', 'Natural Language Processing'),
('AWS', 'AWS'),
('GCP', 'GCP'),
('클라우드 네이티브', 'Cloud Native'),
('컨테이너', 'Container'),
('쿠버네티스', 'Kubernetes'),
('버셀', 'Vercel'),
('깃허브 액션스', 'GitHub Actions'),
('CI/CD', 'CI/CD'),
('데브옵스', 'DevOps'),
('클라우드 보안', 'Cloud Security'),
('데이터 파이프라인', 'Data Pipeline'),
('데이터베이스', 'Database'),
('포스트그레SQL', 'PostgreSQL'),
('몽고DB', 'MongoDB'),
('레디스', 'Redis'),
('엘라스틱서치', 'Elasticsearch'),
('그래프QL', 'GraphQL'),
('스트림 프로세싱', 'Stream Processing'),
('파이썬', 'Python'),
('자바스크립트', 'JavaScript'),
('타입스크립트', 'TypeScript'),
('자바', 'Java'),
('고', 'Go'),
('리액트', 'React'),
('넥스트', 'Next js'),
('뷰', 'Vue js'),
('스벨트', 'Svelte'),
('스프링 부트', 'Spring Boot'),
('패스트API', 'FastAPI'),
('노드', 'Node js'),
('네스트JS', 'NestJS'),
('API', 'API'),
('MSA', 'MSA'),
('웹어셈블리', 'WebAssembly'),
('제로 트러스트', 'Zero Trust'),
('AI 해킹', 'AI Hacking'),
('빅데이터', 'Big Data'),
('데이터 거버넌스', 'Data Governance'),
('데이터 레이크', 'Data Lake'),
('데이터 웨어하우스', 'Data Warehouse'),
('SPA', 'SPA'),
('RESTful API', 'RESTful API'),
('테스트 자동화', 'Test Automation');


INSERT INTO public.rss_feeds (region, feed_url, is_active) VALUES
('DOMESTIC', 'https://techblog.woowahan.com/feed', TRUE),
('DOMESTIC', 'https://engineering.toss.im/feed.xml', TRUE),
('DOMESTIC', 'https://tech.kakao.com/blog/feed', TRUE),
('DOMESTIC', 'https://d2.naver.com/d2.atom', TRUE),
('DOMESTIC', 'https://medium.com/feed/daangn', TRUE),
('DOMESTIC', 'https://medium.com/feed/coupang-engineering', TRUE),
('DOMESTIC', 'https://engineering.linecorp.com/ko/feed', TRUE),
('DOMESTIC', 'https://www.samsungsds.com/kr/tech/feed.xml', TRUE),
('DOMESTIC', 'https://tech.skplanet.com/feed', TRUE),
('DOMESTIC', 'https://medium.com/feed/nhn-techblog', TRUE),
('DOMESTIC', 'https://sendbird.com/blog/ko/feed', TRUE),
('DOMESTIC', 'https://yanolja.github.io/feed.xml', TRUE),
('DOMESTIC', 'https://tech.socarcorp.kr/feed.xml', TRUE),
('DOMESTIC', 'https://blog.banksalad.com/feed', TRUE),
('DOMESTIC', 'https://blog.est.ai/feed', TRUE),
('DOMESTIC', 'https://tech.kakao.com/blog/feed/?tag=react', TRUE),
('DOMESTIC', 'https://techblog.woowahan.com/feed/', TRUE),
('GLOBAL', 'https://ai.googleblog.com/feeds/posts/default', TRUE),
('GLOBAL', 'https://aws.amazon.com/blogs/aws/feed', TRUE),
('GLOBAL', 'https://devblogs.microsoft.com/azure/feed', TRUE),
('GLOBAL', 'https://netflixtechblog.com/feed', TRUE),
('GLOBAL', 'https://engineering.atspotify.com/feed', TRUE),
('GLOBAL', 'https://eng.uber.com/feed', TRUE),
('GLOBAL', 'https://medium.com/feed/airbnb-engineering', TRUE),
('GLOBAL', 'https://shopify.engineering/feed', TRUE),
('GLOBAL', 'https://blog.adobe.com/en/publish/category/technology/feed.xml', TRUE),
('GLOBAL', 'https://engineering.fb.com/feed', TRUE),
('GLOBAL', 'https://github.blog/feed', TRUE),
('GLOBAL', 'https://blog.cloudflare.com/feed', TRUE),
('GLOBAL', 'https://feeds.redhat.com/redhat', TRUE),
('GLOBAL', 'https://developer.nvidia.com/blog/feed', TRUE),
('GLOBAL', 'https://www.elastic.co/blog/feed', TRUE),
('GLOBAL', 'https://react.dev/blog.xml', TRUE),
('GLOBAL', 'https://spring.io/blog.atom', TRUE);