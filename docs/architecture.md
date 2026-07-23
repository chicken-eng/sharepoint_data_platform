# System Architecture Specification

| Document Metadata | Value |
| :--- | :--- |
| **Project Name** | SharePoint Enterprise Data Platform (`sharepoint_data_platform`) |
| **Document Type** | Solution Architecture Specification |
| **Author** | Lead Data Engineer / Solutions Architect |
| **Version** | 1.0.0 |
| **Status** | Approved |
| **Last Updated** | July 2026 |

---

## 1. Executive Summary & Architectural Vision

The **SharePoint Enterprise Data Platform** is designed as a decoupled, fault-tolerant ELT (Extract, Load, Transform) data engine. It bridges unstructured and semi-structured historical files stored across legacy Microsoft SharePoint environments into a centralized, highly indexable, and structured PostgreSQL database.

### Core Architectural Goals
1. **Decoupled Storage and Compute:** Isolate network-heavy file fetching (SharePoint Graph API) from CPU/Memory-heavy parsing and transformation tasks.
2. **Resilience & Rate-Limit Immunity:** Prevent Microsoft Graph API rate-limiting (`429 Too Many Requests`) from breaking pipeline execution by introducing an S3-compatible staging layer (MinIO).
3. **Data Lineage & Auditability:** Ensure absolute traceabilty from any row in the operational relational layer back to its original file, folder path, sheet, and execution run ID.
4. **Zero-Cost Enterprise Blueprint:** Standardize on open-source, containerized technologies (Docker, MinIO, PostgreSQL, Python) capable of running locally or on modest cloud virtual machines.

---

## 2. High-Level Architecture Diagram

[ Microsoft SharePoint ] (Old & New Sites)
           │
           │ (1) Graph API / Azure AD OAuth2
           ▼
[ Ingestion Engine (Python Container) ]
      │                         │
      │ (2) Raw File Dump       │ (3) File Metadata & Hash Register
      ▼                         ▼
[ MinIO Object Storage ]   [ PostgreSQL: metadata schema ]
  (Raw Lake / S3 API)        (files, folders, runs)
      │                         │
      └────────────┬────────────┘
                   │
                   │ (4) Local File Stream & Parse
                   ▼
     [ Transformation Engine ]
                   │
     ┌─────────────┼─────────────┐
     ▼             ▼             ▼
[ bronze ]    [ silver ]    [ gold ]     [ audit ]
Raw Tables   Cleaned DB    Search DB    Logs/Metrics


---

## 3. Storage & Schema Layering Architecture

The database platform uses a 5-tier PostgreSQL schema layout coupled with an external Object Storage landing zone:

+-----------------------------------------------------------------------+
|                         MINIO OBJECT STORE                            |
|  raw-sharepoint-lake / {site} / {year} / {client} / {project} / file  |
+-----------------------------------------------------------------------+
                                   │
                                   ▼
+-----------------------------------------------------------------------+
|                      POSTGRESQL DATABASE SCHEMAS                      |
|                                                                       |
|  1. METADATA : Track files, folders, hashes, versions, paths          |
|  2. BRONZE   : Direct jsonb/tabular dump of raw worksheet contents    |
|  3. SILVER   : Normalized, typed, deduplicated respondent entity data |
|  4. GOLD     : Indexed search tables (optimized for email lookups)    |
|  5. AUDIT    : Execution logs, run durations, failure traces          |
+-----------------------------------------------------------------------+


### Layer Responsibilities

| Layer | System | Format | Retention | Purpose |
| :--- | :--- | :--- | :--- | :--- |
| **Landing** | MinIO | Binary (`.xlsx`, `.csv`, `.docx`) | Permanent | Raw immutable source files downloaded from SharePoint. |
| **`metadata`** | PostgreSQL | Relational | Permanent | Catalog of folder trees, file hashes, and delta detection logic. |
| **`bronze`** | PostgreSQL | `JSONB` / Raw Tables | Ephemeral/Configurable | Raw extracted table rows prior to data cleaning or schema alignment. |
| **`silver`** | PostgreSQL | Normalized Relational | Permanent | Cleaned, typed, deduplicated entities (Respondents, Projects, Clients). |
| **`gold`** | PostgreSQL | Star Schema / Search Indexes | Permanent | Optimized for sub-second operational searches (e.g., email index) and BI. |
| **`audit`** | PostgreSQL | Append-Only Logs | Permanent | Execution metrics, batch stats, error logs, and pipeline health checks. |

---

## 4. Pipeline Execution Lifecycle

The ingestion and transformation process operates through four deterministic phases:

### Phase A: Discovery & Staging (Extract & Load)
1. **Traverse:** Python worker authenticates with Azure AD and queries the Microsoft Graph API to traverse target SharePoint site folders.
2. **De-duplicate:** Calculate file content signatures (`SHA-256`) and compare against `metadata.files`. If hash and `last_modified` match, skip file.
3. **Stage:** Download new/modified files byte-for-byte directly into the MinIO `raw-sharepoint-lake` bucket.
4. **Register:** Record file properties (Path, Author, Size, Hash, Parent Folder ID) into `metadata.files`.

### Phase B: Tabular Parsing (Bronze Load)
1. Stream file contents from MinIO into Python using memory-efficient libraries (`openpyxl` read-only mode for Excel, `polars`/`pyarrow` for CSV).
2. For Excel workbooks, iterate across worksheets (`Sample`, `Export`, `Grids`, etc.) and register sheet names into `metadata.worksheets`.
3. Read raw tabular rows and write them as unstructured JSONB objects or raw string columns directly into `bronze.raw_spreadsheet_rows`.

### Phase C: Normalization & Cleaning (Silver Load)
1. Read untyped records from `bronze`.
2. Apply header standardization rules (e.g., mapping `Emial`, `Email Address`, `E-mail` -> `email`).
3. Cast data types (Dates, Booleans, Phone Numbers), clean strings, and enforce standard formats.
4. Insert structured records into `silver.respondents`, `silver.projects`, and `silver.clients`.

### Phase D: Indexing & Operational Serving (Gold Load)
1. Upsert cleaned records into `gold.respondent_search_index`.
2. Maintain inverted indexes and B-tree indexes on `email`, `phone_number`, and `project_code` for operational lookups.

---

## 5. Security & Isolation Model

* **Secrets Management:** No passwords, tokens, or client secrets reside in code or configuration files. Secrets are injected at container startup via a `.env` file (ignored by `.gitignore`).
* **Graph API Access:** Utilizes Application-Permissions (`Sites.Read.All`, `Files.Read.All`) using OAuth 2.0 Client Credentials flow.
* **Database Access Control:** 
  * `app_pipeline` user: Full privileges on `bronze`, `silver`, `gold`, `metadata`, `audit`.
  * `app_read_only` user: Restricted read access exclusively to `gold` and `silver` schemas.
