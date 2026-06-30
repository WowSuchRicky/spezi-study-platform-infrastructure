<!--
This source file is part of the Stanford Spezi open source project

SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT
-->

# Docker Local Development

Local development environment for your Spezi-based study platform. Provides backing services (PostgreSQL, Keycloak) and optionally runs the full stack using published container images for your server and web applications.

This is part of the infrastructure template and must be rendered before use — see [Step 0 in the root README](../README.md#step-0-render-the-template). `docker-compose.yml` and `.env.example` both reference `__PLACEHOLDER__` image names until then.

## Setup

```bash
cp .env.example .env
```

## Full Stack

```bash
docker compose up -d
```

| Service        | URL                         |
| -------------- | --------------------------- |
| Web            | http://localhost:3000       |
| Server         | http://localhost:8080       |
| Keycloak       | http://localhost:8180       |
| Keycloak Admin | http://localhost:8180/admin |
| Server DB      | localhost:5432              |

## Backing Services Only

For running server or web natively:

```bash
docker compose up -d server-db keycloak-db keycloak
```

Then run server/web from their repos against localhost ports.

## Migrations

```bash
docker compose run --rm server-migrate
```

## Test Users

All passwords: `password123`

| Email              | Role        |
| ------------------ | ----------- |
| leland@example.com | admin       |
| jane@example.com   | researcher  |
| alice@example.com  | participant |

## Keycloak Admin

Username: `admin`, password: `admin` (configurable in `.env`)

## Reset

```bash
docker compose down -v
```
