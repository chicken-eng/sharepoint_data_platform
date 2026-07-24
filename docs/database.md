# Database Design & Data Dictionary

## Architectural Strategy: The Single Source of Truth
This database replaces the legacy manual database entirely. It is designed as a unified Medallion Architecture (Data Platform) that handles structured project data from SharePoint, unstructured website scrapes, and global compliance (Unsubscribes/Blacklists) in one automated system.

## Core Schemas

### 1. `audit` Schema
Manages pipeline execution state, tracking every automated run, success rates, and errors.

### 2. `metadata` Schema
Manages idempotency and source tracking.
* **`sources`:** Accommodates multiple origins, allowing us to ingest 'SharePoint' files alongside 'Website_Scrapes' without needing separate databases.

### 3. `bronze` Schema
The immutable raw data layer. 
* **`raw_data`:** Uses `JSONB` to swallow messy Excel rows and scraped website payloads alike, preventing schema-drift pipeline crashes.

### 4. `silver` Schema (The Master Data & Compliance Layer)
* **Master Respondent (`respondents`):** The single, globally deduplicated record of a person. Includes `consent_status` ('Opt-In', 'Unsubscribed', 'Blacklisted') to handle global communication permissions across all projects.
* **Compliance Engine (`compliance_events`):** An audit log detailing exactly when and why a respondent was blacklisted or opted out, satisfying GDPR/compliance requirements.
* **Master Data Management (`respondent_profile_history`):** Logs every demographic claim (Ethnicity, Gender, Location) across time to detect fraudulent actors who change their profiles to qualify for studies.
* **Lifecycle Mapping (`project_participation`):** Tracks respondent pipeline status (e.g., Identified, Considered, Participated) derived dynamically from SharePoint folder paths.
* **Independent Leads:** Because `project_id` is isolated in `project_participation`, website scrapes can exist as respondents without being artificially tied to a specific project.

### 5. `gold` Schema
* **`respondent_search_index`:** An ultra-fast table used by recruiters to search for candidates. It collapses history into JSON arrays (`known_aliases`, `known_phones`) and exposes `consent_status` and `fraud_risk_score` so recruiters instantly know who is safe to contact.
* **`ai_semantic_embeddings`:** Powered by `pgvector`. Stores mathematical representations of historical survey answers and methodology documents for future AI pre-screening.
