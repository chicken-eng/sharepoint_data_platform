# Business & Technical Requirements Specification

| Document Metadata | Value |
| :--- | :--- |
| **Project Name** | SharePoint Enterprise Data Platform (`sharepoint_data_platform`) |
| **Author** | Lead Data Engineer / Database Administrator |
| **Organization** | Field Scope International |
| **Version** | 1.0.0 |
| **Status** | Approved |
| **Last Updated** | July 2026 |

---

## 1. Executive Summary & Business Problem

Field Scope International specializes in market research recruitment. Since approximately 2016, critical operational data—including respondent details, project specifications, screeners, and quota tracking—has been stored in flat files across two distinct Microsoft SharePoint site environments:

*   **Legacy Environment ("Old Site"):** `Recruitment Department / Completed Projects /`
*   **Current Environment ("New Site"):** `Projects / Past Projects /`

### The Problem
While active study records from 2022 onwards exist within a centralized PostgreSQL instance, pre-2022 historical records reside exclusively inside semi-structured and unstructured files (`.xlsx`, `.xls`, `.csv`, `.docx`) nested within deep year/type/client/project directory structures. 

When historical lookups are required (most frequently by **email address**), team members must manually navigate SharePoint folders and open individual workbooks. This process is slow, non-scalable, susceptible to human error, and prevents organizational cross-project analytics.

---

## 2. Project Vision & Strategic Goals

The objective of the **SharePoint Enterprise Data Platform** is to build an automated, fault-tolerant, and lineaged ingestion pipeline that transforms SharePoint file stores into a structured, queryable relational data asset in PostgreSQL.

### Core Objectives
1. **Centralize Historical Intelligence:** Convert scattered spreadsheet rows and document metadata into relational records accessible via standardized SQL queries.
2. **Preserve System of Record:** Treat SharePoint as the immutable upstream system of record without modifying or corrupting source files.
3. **Establish End-to-End Lineage:** Ensure every extracted record in the database can be traced back to its specific SharePoint site, path, file, worksheet, and ingestion execution ID.
4. **Enable Operations & Analytics:** Provide rapid operational search capability (sub-second respondent email lookup) and establish a foundation for downstream BI tools and machine learning.

---

## 3. Scope Boundary

### In-Scope
* **Discovery & Crawling:** Automated traversal of SharePoint nested directory structures (`Year / Project Type / Client / Project`).
* **Raw Staging (Bronze Landing):** Automated download and staging of raw source files into an open-source local Object Storage landing layer (MinIO).
* **Parsing & Extraction:**
  * Tabular extraction from Excel workbooks (`.xlsx`, `.xls`) across multiple sheets (e.g., `Sample`, `Export`, `Grids`).
  * Tabular extraction from flat CSV files.
  * Metadata and structured text extraction from Microsoft Word documents (`.docx`) in `Project Materials`.
* **Data Lineage & Metadata Management:** Full recording of folder paths, file properties, worksheet inventories, and execution state in PostgreSQL `metadata` and `audit` schemas.
* **Target Storage:** Structuring data into PostgreSQL layered schemas (`bronze`, `silver`, `gold`).
* **Incremental Ingestion:** Delta-based ingestion to process only modified or newly created files based on cryptographic hash and modification timestamps.
* **Containerization:** Full local deployment orchestration via Docker and Docker Compose.

### Out-of-Scope (Phase 1 Initial Release)
* Modifying, moving, or deleting original files within SharePoint.
* Real-time event streaming (batch ingestion is sufficient for historical and operational demands).
* Live multi-tenant web application UI creation (data will be exposed via PostgreSQL endpoints for SQL engines/BI).

---

## 4. Functional Requirements (FR)

| ID | Category | Description | Priority |
| :--- | :--- | :--- | :--- |
| **FR-01** | Discovery | The system MUST authenticate via Azure AD App Registration (Microsoft Graph API) and recursively discover all files in target SharePoint paths. | High |
| **FR-02** | Metadata Tracking | The system MUST record document properties (File Name, Extension, File Size, Created Date, Last Modified Date, Author, Content Hash, and Path Hierarchy) prior to data extraction. | High |
| **FR-03** | Staging | The system MUST write extracted raw files byte-for-byte to an S3-compatible Object Store (MinIO) acting as the raw landing zone. | High |
| **FR-04** | Tabular Parsing | The system MUST extract data from Excel workbooks containing multiple sheets without failing when sheet names or schema layouts vary. | High |
| **FR-05** | Schema Normalization | The system MUST map heterogeneous column header naming conventions across legacy spreadsheets into standardized database schema fields in the `silver` layer. | High |
| **FR-06** | Operational Search | The system MUST index primary key search attributes (specifically respondent email addresses) to enable sub-second querying across historical project datasets. | High |
| **FR-07** | Incremental Processing | The system MUST skip processing files whose content hash and last-modified timestamp match an already successfully ingested record in the audit registry. | Medium |
| **FR-08** | Lineage Tracking | Every record inserted into `bronze`, `silver`, and `gold` layers MUST contain foreign key references to the source file metadata record and execution batch run ID. | High |

---

## 5. Non-Functional Requirements (NFR)

### NFR-01: Idempotency & Repeatability
Running the pipeline multiple times over the exact same source data set MUST produce identical database states without creating duplicate records or throwing constraint violations.

### NFR-02: Resilience & Throttling Mitigation
The Microsoft Graph API integration MUST handle rate-limiting (`HTTP 429 Too Many Requests`) gracefully using exponential backoff and randomized jitter algorithms.

### NFR-03: Performance & Resource Efficiency
Spreadsheet parsing MUST utilize streaming or memory-efficient readers (e.g., `openpyxl` read-only mode or `polars`/`pyarrow`) to ensure processing large workbooks does not trigger Out-Of-Memory (OOM) errors on containerized hosts.

### NFR-04: Security & Compliance
* All credentials, API client secrets, and database passwords MUST be injected via environment variables and NEVER hardcoded in source repositories.
* Personally Identifiable Information (PII)—specifically emails and contact details—must be stored in dedicated PostgreSQL schemas with restricted access control policies.

### NFR-05: Observability & Auditability
Every pipeline run MUST produce structured operational logs (JSON format) detailing started tasks, success counts, failed records, execution durations, and error stack traces recorded in the `audit` schema.

---

## 6. Architectural Constraints & Assumptions

1. **Zero Financial Cost:** All software components, databases, object stores, and orchestration utilities MUST utilize free, open-source tools (Python, PostgreSQL, MinIO, Docker).
2. **Access Rights:** The pipeline operates using an App-Only authentication model via Microsoft Azure AD with granted Graph API permissions (`Sites.Read.All` / `Files.Read.All`).
3. **Data Volume:** Total historical archive volume is estimated under 100 GB, making distributed compute clusters (e.g., Apache Spark) unnecessary; single-node Python containerized execution is sufficient.
