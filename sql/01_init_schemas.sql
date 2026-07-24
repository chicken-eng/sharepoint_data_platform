-- ==============================================================================
-- 01_init_schemas.sql
-- Initializes the 5-layer Medallion architecture.
-- Replaces the legacy manual database completely. Acts as the Single Source of Truth.
-- ==============================================================================

CREATE SCHEMA IF NOT EXISTS audit;
CREATE SCHEMA IF NOT EXISTS metadata;
CREATE SCHEMA IF NOT EXISTS bronze;
CREATE SCHEMA IF NOT EXISTS silver;
CREATE SCHEMA IF NOT EXISTS gold;

CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS vector; 

-- ==============================================================================
-- AUDIT LAYER
-- ==============================================================================
CREATE TABLE audit.pipeline_runs (
    run_id BIGSERIAL PRIMARY KEY,
    run_type VARCHAR(50) NOT NULL, 
    status VARCHAR(50) NOT NULL, 
    start_time TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    end_time TIMESTAMP WITH TIME ZONE,
    records_processed INT DEFAULT 0,
    error_message TEXT
);

-- ==============================================================================
-- METADATA LAYER
-- Added 'source_system' to handle Website Scrapes alongside SharePoint files
-- ==============================================================================
CREATE TABLE metadata.sources (
    source_id BIGSERIAL PRIMARY KEY,
    source_system VARCHAR(100) NOT NULL, -- e.g., 'SharePoint', 'Website_Scrape', 'Manual_Import'
    source_name VARCHAR(255) NOT NULL, 
    source_url TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE metadata.files (
    file_id BIGSERIAL PRIMARY KEY,
    source_id BIGINT REFERENCES metadata.sources(source_id),
    external_item_id VARCHAR(255) UNIQUE NOT NULL, -- SharePoint ID or Scrape Job ID
    file_name VARCHAR(500) NOT NULL,
    file_extension VARCHAR(10) NOT NULL,
    logical_path TEXT NOT NULL, 
    minio_object_path TEXT NOT NULL, 
    file_hash VARCHAR(256) NOT NULL, 
    last_modified_externally TIMESTAMP WITH TIME ZONE NOT NULL,
    last_processed_run_id BIGINT REFERENCES audit.pipeline_runs(run_id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE metadata.worksheets (
    worksheet_id BIGSERIAL PRIMARY KEY,
    file_id BIGINT REFERENCES metadata.files(file_id),
    sheet_name VARCHAR(255) NOT NULL,
    row_count INT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(file_id, sheet_name)
);

-- ==============================================================================
-- BRONZE LAYER
-- Raw JSONB. Accepts both messy Excel data AND unstructured website scrapes.
-- ==============================================================================
CREATE TABLE bronze.raw_data (
    bronze_id BIGSERIAL PRIMARY KEY,
    worksheet_id BIGINT REFERENCES metadata.worksheets(worksheet_id),
    row_number INT NOT NULL,
    raw_payload JSONB NOT NULL, 
    ingested_run_id BIGINT REFERENCES audit.pipeline_runs(run_id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE bronze.raw_documents (
    bronze_doc_id BIGSERIAL PRIMARY KEY,
    file_id BIGINT REFERENCES metadata.files(file_id),
    raw_text TEXT NOT NULL, 
    ingested_run_id BIGINT REFERENCES audit.pipeline_runs(run_id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ==============================================================================
-- SILVER LAYER
-- ==============================================================================
CREATE TABLE silver.projects (
    project_id BIGSERIAL PRIMARY KEY,
    project_number VARCHAR(100), 
    project_year INT,
    project_type VARCHAR(100),
    client_name VARCHAR(255),
    project_name VARCHAR(500) NOT NULL,
    topic TEXT,                  
    methodology TEXT,            
    source_file_id BIGINT REFERENCES metadata.files(file_id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(project_year, project_type, client_name, project_name)
);

-- Unified Respondent Table with Compliance & Consent Tracking
CREATE TABLE silver.respondents (
    respondent_id BIGSERIAL PRIMARY KEY,
    primary_email_address VARCHAR(255) UNIQUE, 
    latest_first_name VARCHAR(255),
    latest_last_name VARCHAR(255),
    latest_phone_number VARCHAR(50),
    consent_status VARCHAR(50) DEFAULT 'Opt-In', -- 'Opt-In', 'Unsubscribed', 'Blacklisted'
    fraud_flag BOOLEAN DEFAULT FALSE, 
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Tracks WHY someone was blacklisted or unsubscribed
CREATE TABLE silver.compliance_events (
    event_id BIGSERIAL PRIMARY KEY,
    respondent_id BIGINT REFERENCES silver.respondents(respondent_id),
    event_type VARCHAR(50) NOT NULL, -- 'Unsubscribe', 'Blacklist_Added', 'GDPR_Delete'
    reason_description TEXT,
    event_date TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    logged_by VARCHAR(100) DEFAULT 'System'
);

CREATE TABLE silver.respondent_profile_history (
    history_id BIGSERIAL PRIMARY KEY,
    respondent_id BIGINT REFERENCES silver.respondents(respondent_id),
    attribute_name VARCHAR(100) NOT NULL, 
    attribute_value VARCHAR(500),         
    observed_date TIMESTAMP WITH TIME ZONE, 
    source_project_id BIGINT REFERENCES silver.projects(project_id),
    source_bronze_id BIGINT REFERENCES bronze.raw_data(bronze_id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE silver.project_participation (
    participation_id BIGSERIAL PRIMARY KEY,
    project_id BIGINT REFERENCES silver.projects(project_id),
    respondent_id BIGINT REFERENCES silver.respondents(respondent_id),
    interaction_level VARCHAR(100), 
    incentive INT,                  
    currency VARCHAR(10),           
    last_activity_date TIMESTAMP WITH TIME ZONE,
    source_bronze_id BIGINT REFERENCES bronze.raw_data(bronze_id), 
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(project_id, respondent_id)
);

CREATE TABLE silver.survey_responses (
    response_id BIGSERIAL PRIMARY KEY,
    participation_id BIGINT REFERENCES silver.project_participation(participation_id),
    question_text TEXT NOT NULL,
    answer_text TEXT,
    source_bronze_id BIGINT REFERENCES bronze.raw_data(bronze_id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ==============================================================================
-- GOLD LAYER
-- ==============================================================================
CREATE TABLE gold.respondent_search_index (
    search_id BIGSERIAL PRIMARY KEY,
    respondent_id BIGINT REFERENCES silver.respondents(respondent_id),
    primary_email_address VARCHAR(255),
    known_aliases JSONB,       
    known_phones JSONB,        
    consent_status VARCHAR(50), 
    fraud_risk_score INT,      
    total_projects_participated INT,
    latest_project_date TIMESTAMP WITH TIME ZONE,
    participation_history JSONB 
);

CREATE INDEX idx_gold_search_email ON gold.respondent_search_index(primary_email_address);
CREATE INDEX idx_gold_search_fuzzy_name ON gold.respondent_search_index USING GIN (known_aliases);

CREATE TABLE gold.ai_semantic_embeddings (
    embedding_id BIGSERIAL PRIMARY KEY,
    response_id BIGINT REFERENCES silver.survey_responses(response_id),
    content_text TEXT NOT NULL,
    semantic_vector vector(1536), 
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
