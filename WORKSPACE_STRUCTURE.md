# Orpheus Project - Workspace Structure

This workspace contains all components of the Orpheus secure messenger ecosystem.

## Workspace Configuration

The workspace is defined in [orpheus_project.code-workspace](orpheus_project.code-workspace) and includes 5 components:

## 1. Orpheus Client (Mobile) 📱
**Path**: `.` (current directory - `d:\orpheus_client`)
**Technology**: Flutter (Dart 3.0+)
**Platform**: Android
**CLAUDE.md**: [CLAUDE.md](CLAUDE.md)

**Purpose**: Mobile messenger application with end-to-end encryption

**Key Features**:
- E2E encryption (X25519 + ChaCha20-Poly1305)
- Real-time messaging via WebSocket
- WebRTC voice/video calls
- Oracle of Orpheus AI assistant
- Notes Vault (encrypted notes)
- Group chats (Rooms)
- Duress mode and panic wipe
- Desktop Link (QR-based pairing - in development)

**Main Files**:
- [lib/main.dart](lib/main.dart) - entry point
- [lib/services/crypto_service.dart](lib/services/crypto_service.dart) - E2E encryption
- [lib/services/websocket_service.dart](lib/services/websocket_service.dart) - real-time messaging
- [lib/services/database_service.dart](lib/services/database_service.dart) - local SQLite storage

---

## 2. Orpheus Desktop 🖥️
**Path**: `../orpheus_desctop/orpheus_desktop`
**Technology**: C# (.NET 8.0), WinUI 3 (Windows App SDK)
**Platform**: Windows 10/11 (x86, x64, ARM64)
**CLAUDE.md**: [orpheus_desktop/CLAUDE.md](../orpheus_desctop/orpheus_desktop/CLAUDE.md)

**Purpose**: Windows desktop application for Orpheus messenger

**Key Features**:
- Desktop Link - QR-based pairing with mobile client
- Contact sync with mobile
- Real-time messaging sync
- Notes Vault sync
- E2E encryption matching mobile client

**Architecture**: MVVM (Model-View-ViewModel) with WinUI 3

---

## 3. Orpheus Backend ⚙️
**Path**: `../Programs/orpheus`
**Technology**: Python 3.11+, FastAPI, PostgreSQL, Redis
**Platform**: Linux server (Docker)
**CLAUDE.md**: [orpheus/CLAUDE.md](../Programs/orpheus/CLAUDE.md)

**Purpose**: Main backend server - message routing, user management, payments

**Key Features**:
- Zero-knowledge architecture (server never decrypts messages)
- WebSocket server for real-time messaging
- Multi-node scaling via Redis pub/sub
- Push delivery over the persistent WebSocket (client migrated off Firebase/FCM to a
  persistent foreground service; the backend FCM path is being deprecated)
- TRON blockchain payment processing
- Oracle AI integration (support chat)
- PostgreSQL for user data, messages, rooms
- Multi-host fallback (api.orpheus.click + legacy)
- HTTP fallback for critical WebRTC signals

**Main Files**:
- main.py - WebSocket server, message routing
- payments.py - TRON blockchain payments
- redis_bridge.py - Redis pub/sub for scaling
- app/admin_api.py - admin panel
- app/auth_api.py - registration, login, key exchange
- app/rooms_api.py - group chats
- app/support_api.py - support chat with Oracle AI

---

## 4. Orpheus Mailer Relay 📧
**Path**: `C:/Users/titan/GolandProjects/orpheus_main_relay`
**Technology**: Go 1.22+
**Platform**: Linux server
**CLAUDE.md**: [orpheus_main_relay/CLAUDE.md](C:/Users/titan/GolandProjects/orpheus_main_relay/CLAUDE.md)

**Purpose**: SMTP relay service (HTTPS → SMTP)

**Key Features**:
- Relays emails via HTTPS (443) → SMTP (465/587)
- Solves PaaS platforms blocking SMTP ports
- Token-based authentication
- Idempotency support
- Zero external dependencies (stdlib only)
- Used by main backend for email delivery

**API**:
- `GET /healthz` - health check
- `POST /send` - send email (requires Bearer token)

---

## 5. Orpheus Site 🌐
**Path**: `../Orpheus_Site`
**Technology**: React 18, TypeScript, Vite, TailwindCSS
**Platform**: Static site (Vercel/Netlify/nginx)
**CLAUDE.md**: [Orpheus_Site/CLAUDE.md](../Orpheus_Site/CLAUDE.md)

**Purpose**: Public website - landing page, documentation, downloads

**Key Features**:
- Orpheus project landing page
- Feature showcase
- Download links for mobile/desktop apps
- Documentation (rendered from markdown)
- Multi-language (EN/RU)
- Responsive design
- Fast loading and SEO optimization

**Tech Stack**:
- React Router - client-side routing
- Framer Motion - animations
- react-markdown - documentation rendering
- Lucide React - icons

---

## Technology Stack Summary

| Component | Language | Framework | Database | Deployment |
|-----------|----------|-----------|----------|------------|
| Mobile Client | Dart | Flutter | SQLite | Play Store (Android) |
| Desktop Client | C# | WinUI 3 | SQLite | MSIX (Windows) |
| Backend | Python | FastAPI | PostgreSQL, Redis | Docker (VPS) |
| Mailer Relay | Go | stdlib | - | systemd (VPS) |
| Website | TypeScript | React + Vite | - | Static hosting |

---

## Communication Protocol

**End-to-End Encryption**:
- Key exchange: X25519 (ECDH)
- Encryption: ChaCha20-Poly1305 (AEAD)
- Server only routes encrypted messages (zero-knowledge)

**Transport**:
- WebSocket for real-time messaging
- HTTP fallback for critical WebRTC signals (call-offer, call-answer, hang-up)
- Multi-host fallback for reliability

**Authentication**:
- JWT tokens for API
- E2E encrypted identity verification
- Duress mode support

---

## Development Workflow

### Git Repositories
Each component has its own git repository:
- `orpheus_client` - mobile app
- `orpheus_desktop` - desktop app
- `orpheus` - backend server
- `orpheus_main_relay` - mailer relay
- `Orpheus_Site` - website

### Working with Claude
Each component has a `CLAUDE.md` file with specific instructions for that technology stack. When working on a component, Claude will use the relevant CLAUDE.md to understand the codebase conventions.

### Cross-Component Changes
When making changes that affect multiple components (e.g., WebSocket protocol, encryption), ensure compatibility:
1. **Backend changes**: update first, maintain backwards compatibility
2. **Mobile/Desktop clients**: update to support new features
3. **Test**: verify communication between components

### Testing
- **Mobile**: `flutter test`
- **Desktop**: `dotnet test`
- **Backend**: `pytest`
- **Mailer**: `go test ./...`
- **Website**: `npm test` (if configured)

---

## Security Notes

**CRITICAL**: All components follow zero-knowledge architecture:
- Server NEVER decrypts user messages
- Private keys NEVER leave user devices
- Duress mode returns fake/empty data
- All crypto operations audited

**Each component must**:
- NEVER log sensitive data (keys, passwords, decrypted content)
- Use secure storage (FlutterSecureStorage, Windows Credential Manager, etc.)
- Validate all inputs (SQL injection, XSS prevention)
- Use TLS/HTTPS in production

---

## Communication Language
- **Code & Comments**: English
- **UI Text**: Multi-language (EN priority, RU secondary) via localization
- **Documentation**: Russian (user is Russian-speaking)
- **Git Commits**: English

---

## Project Status

**Production**:
- ✅ Mobile Client (v1.x)
- ✅ Backend (v1.x)
- ✅ Mailer Relay (v1.x)
- ✅ Website (v1.x)

**In Development**:
- 🚧 Desktop Client (beta)
- 🚧 Desktop Link feature (mobile ↔ desktop sync)

---

## Related Files
- [orpheus_project.code-workspace](orpheus_project.code-workspace) - VSCode workspace config
- [CLAUDE.md](CLAUDE.md) - Mobile client instructions
- [README.md](README.md) - Mobile client documentation
- [RELEASE_PLAN.md](RELEASE_PLAN.md) - Release roadmap
- [AI_WORKLOG.md](AI_WORKLOG.md) - Development log
