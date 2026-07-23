# SharePoint Data Platform

> A production-inspired data engineering platform for discovering, cataloguing, extracting, transforming, and serving structured data from SharePoint into PostgreSQL.

---

## Overview

Many organisations rely on SharePoint to store operational data in Excel, CSV, Word and other Office documents. While SharePoint is excellent for document management, it becomes increasingly difficult to search, analyse and report on data spread across thousands of files and folders.

This project aims to solve that problem by building an enterprise-inspired data platform that transforms SharePoint into a searchable and structured data source.

The platform automatically discovers files, extracts structured data from Excel and CSV documents, captures metadata, and loads curated datasets into PostgreSQL for analytics, reporting and operational use.

---

## Problem Statement

The project is based on a real-world business challenge within a market research organisation.

Since 2016, project information has been stored across multiple SharePoint sites containing thousands of spreadsheets, survey exports and project documents.

Searching historical information requires manually opening numerous files, making reporting slow and inefficient.

---

## Objectives

- Discover and catalogue SharePoint files
- Capture file and folder metadata
- Extract structured data from Excel and CSV files
- Support incremental processing
- Maintain full data lineage
- Clean and standardise imported data
- Store curated datasets in PostgreSQL
- Enable fast SQL-based searching and reporting

---

## Planned Architecture

SharePoint

↓

Metadata Discovery

↓

Extraction Engine

↓

Bronze Layer (Raw)

↓

Silver Layer (Validated)

↓

Gold Layer (Business Ready)

↓

PostgreSQL

↓

Metabase / BI

---

## Technologies

- Python
- PostgreSQL
- Microsoft Graph API
- Pandas
- SQLAlchemy
- Docker
- GitHub Actions
- Pytest

---

## Project Status

🚧 In Development

Current Phase:

- Project Planning
- Architecture Design
- Database Design

---

## Documentation

Project documentation is located within the `/docs` directory.

It includes:

- Requirements
- Architecture
- Database Design
- ETL Design
- Security
- Testing
- Deployment
- Architecture Decision Records (ADR)

---

## Repository Structure

```

docs/
architecture/
database/
deployment/
requirements/

src/

sql/

tests/

configs/

sample_data/

```

---

## License

MIT License
