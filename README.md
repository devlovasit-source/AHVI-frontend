# AHVI Frontend — Closed Beta MVP

AHVI is an AI-powered personal assistant platform built around:
- Style
- Planning
- Preparation

This repository contains the Flutter frontend powering the current AHVI closed-beta MVP experience.

---

# Current MVP Scope

The frontend currently supports the primary AHVI user journeys, including:

- AI style chat
- wardrobe management
- editorial outfit boards
- workout + style experiences
- planning and pack flows
- saved boards and personalization flows
- supporting lifestyle workflows and integrations

The current phase is focused on stabilization, UI consolidation, orchestration consistency, and beta-readiness refinement.

---

# Frontend Structure

The Flutter app is organized around the primary user-facing AHVI experiences:

- authentication and onboarding screens
- home/navigation entry points
- AI style chat interface
- wardrobe upload, capture, and management screens
- editorial outfit board rendering
- saved board and profile-related flows
- workout, planning, and supporting lifestyle screens
- shared UI widgets and theme utilities
- frontend service layer for backend/API communication
- Appwrite-based authentication and data access integration

The current frontend is functional for the closed-beta MVP flows and is undergoing active stabilization, UI consolidation, and component-level cleanup.

---

# Tech Stack

- Flutter
- Appwrite
- Cloud Run backend APIs
- AI orchestration services
- Cloud storage integrations

---

# Current Stabilization Focus

Ongoing refinement areas include:

- API consistency
- board rendering polish
- UX consolidation
- loading and error handling
- orchestration consistency across flows
- APK/demo stability
- beta QA and refinement

---

# Environment Configuration

Frontend environment variables are configured using `.env`.

Only public frontend configuration values should be included in frontend environment files.

Sensitive backend credentials and infrastructure secrets are managed separately through backend/runtime configuration.

---

# Status

Current phase:
- Closed Beta
- Closed-beta MVP stabilization
- Core frontend flows implemented
- Active refinement and consolidation ongoing
