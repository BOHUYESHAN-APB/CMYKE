# Deep Research Export Service (Agent C)
Date: 2026-02-17

## Summary
- Added `DeepResearchExportService` to export HTML + metadata to `Documents/cmyke/exports` and optionally convert to docx/pdf via Pandoc.
- Added a `ChatExportService` wrapper method to call the new service.

## Logic
- `exportHtml` always writes the HTML archive and a metadata JSON (includes `exported_at`, `format`, and normalized `metadata`).
- For docx/pdf: if Pandoc is available, run `pandoc --from=html --to=<format> input.html -o output.<ext>`.
- If Pandoc is missing or conversion fails, the service returns warnings and keeps the HTML export.
- For pptx/xlsx: conversion is not implemented yet; a warning is returned.

## External Dependencies
- Optional: `pandoc` on PATH for docx/pdf conversion.

## Files Changed
- lib/core/services/deep_research_export_service.dart
- lib/core/services/chat_export_service.dart
- docs/agents/agent_export.md

## Open Issues
- No PPTX/XLSX converter wired.
- Pandoc PDF output depends on a system PDF engine (e.g., LaTeX). If missing, conversion will fail and HTML remains.
