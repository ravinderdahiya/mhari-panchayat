# Project Behavior Map

## Slide 1: Project Overview
- Project: `mhari-panchayat`
- Main layers:
  - `backend` (Laravel API)
  - `admin-panel` (React + Vite + TS)
  - `frontend` (Flutter App)
- Objective: define responsibilities, interaction, and delivery timeline for meeting discussion.

---

## Slide 2: Backend Responsibilities
- Provide REST API for all core business logic.
- Manage authentication and session state.
- Handle OTP registration, login, password reset.
- Enforce roles and permissions for each action.
- Manage complaint lifecycle and survey submission.
- Provide master data endpoints and asset type administration.
- Manage village asset (GIS) data and admin CRUD operations.

---

## Slide 3: Admin Panel Responsibilities
- Authenticate user via `POST /api/auth/login`.
- Persist JWT/Bearer token in local storage.
- Retrieve current user with `GET /api/auth/me`.
- Render UI based on user roles and permissions.
- Display dashboards, complaints, surveys, users, citizens, roles, master data.
- Execute complaint actions: acknowledge, survey, resolve, verify, transfer, reopen.
- Manage master data entities and asset type admin interfaces.
- Display village asset listing and management pages.

---

## Slide 4: App Responsibilities
- Serve mobile/web client users through Flutter.
- Integrate with same backend API contract.
- Enable surveyor/officer workflows and complaint submission.
- Support OTP-based registration and review status.
- Fetch location, asset, and survey data from backend.
- Complement admin-panel by exposing citizen-facing interactions.

---

## Slide 5: API Interaction Map
- `admin-panel` → `backend`: login, getMe, master data, complaints, asset types, village assets.
- `frontend` → `backend`: survey work, registrations, location, assets, complaint filing.
- `backend` enforces:
  - auth using Sanctum
  - permissions per endpoint
  - role-based access for super_admin, state_admin, district_admin

---

## Slide 6: Key User Flows
### Login & Session
- User opens admin-panel.
- Login form → `POST /api/auth/login`.
- Save token and load `GET /api/auth/me`.
- Render pages according to role.

### Complaint Workflow
- File complaint → `POST /api/complaints`.
- Fetch complaints → `GET /api/complaints`.
- Open complaint detail → `GET /api/complaints/{id}`.
- Acknowledge / survey / resolve / verify / transfer / rate / reopen via patch endpoints.

### Master Data Workflow
- Load dropdowns with `GET /api/master/{entity}`.
- Create/update/delete master items via `/api/master/{entity}`.
- Admin only write access via `permission:master_data.manage`.

---

## Slide 7: Timeline Phases
### Phase 1: Setup
- Backend environment, composer install, migrations.
- Admin-panel install and local run.
- App `flutter pub get` and build validation.

### Phase 2: Core Integration
- Implement auth and session restore.
- Validate API base URL and token handling.
- Build basic dashboard and complaint list views.

### Phase 3: Admin Features
- Master data CRUD pages.
- User and citizen management.
- Role/permission editor.
- Village asset management.

### Phase 4: App Integration
- Mobile registration and survey flows.
- Complaint filing and status retrieval.
- Location/asset lookup.

### Phase 5: QA & Deployment
- API smoke tests.
- End-to-end admin-panel test.
- App regression and build.
- Deployment checklist.

---

## Slide 8: Meeting Action Items
- Confirm backend API contract for each UI feature.
- Confirm role/permission rules for admin panel.
- Confirm mobile app endpoints and required fields.
- Assign next deliverables:
  - Backend endpoint completion
  - Admin-panel page flows
  - App feature integration
- Schedule follow-up for integration validation.
