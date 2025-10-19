# Reflex-KSys Database Deployment

TimescaleDB 17 (PostgreSQL 17) + pgai + pg_cron deployment for Reflex-KSys SCADA system.

## 📦 Contents

- **backup/**: Full database backups
  - `ecoanp_full_backup_20251019.dump` (25MB) - Highly compressed (pg_restore required)
  - `ecoanp_backup_20251019.dump` (27MB) - Standard custom format
  - `globals.sql` (946B) - Database roles and global objects
- **migrations/**: SQL migration scripts
  - Virtual tag calculation functions
  - Training/forecasting schema migrations
- **init/**: Database initialization scripts
- **docker-compose.yml**: Multi-container orchestration

## 🚀 Quick Start

### 1. Start Database

```bash
docker-compose up -d
```

This starts:
- **pgai-db**: TimescaleDB 17 with pgai extensions (port 6543→5432)
- **pgai-ollama**: AI model serving (port 11534→11434)
- **pgai-vectorizer-worker**: Automatic embedding generation

### 2. Restore Database

**Step 1: Restore global objects**
```bash
docker cp backup/globals.sql pgai-db:/tmp/
docker exec -i pgai-db psql -U postgres < /tmp/globals.sql
```

**Step 2: Create database**
```bash
docker exec -it pgai-db psql -U postgres -c "CREATE DATABASE ecoanp"
```

**Step 3: Restore from compressed backup**
```bash
# Copy backup into container
docker cp backup/ecoanp_full_backup_20251019.dump pgai-db:/tmp/

# Restore using pg_restore (custom format)
docker exec pgai-db pg_restore -U postgres -d ecoanp --no-owner --no-privileges /tmp/ecoanp_full_backup_20251019.dump
```

**Note:** TimescaleDB circular foreign-key warnings are expected and safe to ignore.

### 3. Apply Migrations (Optional)

```bash
# Apply virtual tag migrations
docker exec -i pgai-db psql -U postgres -d ecoanp < migrations/01_create_virtual_tag_table.sql
docker exec -i pgai-db psql -U postgres -d ecoanp < migrations/02_create_virtual_tag_functions.sql
# ... (apply all in order)
```

### 4. Verify Installation

```bash
# Connect to database
docker exec -it pgai-db psql -U postgres -d ecoanp

# Check TimescaleDB version
SELECT * FROM timescaledb_information.version;

# Check hypertables
SELECT * FROM timescaledb_information.hypertables;

# Check pg_cron jobs
SELECT * FROM cron.job;

# Exit
\q
```

## 🗄️ Database Schema

### Core Tables

- **influx_hist** (274K+ records): Time-series sensor data (hypertable)
- **influx_tag**: Sensor definitions (tag_name, description, unit)
- **influx_qc_rule**: QC thresholds (min, max, warning, critical)
- **alarm_history**: Rule-based alarm events
- **ai_knowledge_base**: RAG knowledge base with pgvector embeddings

### ML/Forecasting Tables

- **training_scenarios**: ML training configurations
- **training_evaluations**: Model performance metrics
- **deployed_models**: Active production models (binary BYTEA)
- **forecast_results**: Online predictions (5-min intervals)
- **forecast_performance**: Accuracy tracking (hourly aggregates)
- **feature_configs**: Feature engineering definitions

### Views

- **influx_latest**: Current sensor values (most recent per tag)
- **influx_agg_1m/10m/1h/1d**: Time-bucket aggregations (continuous aggregates)

### Virtual Tags

Calculated via PostgreSQL function `calculate_virtual_tags()`:
- Scheduled by pg_cron (every 1 minute)
- Derived sensor values (e.g., flow rates, efficiency metrics)

## 🔧 Configuration

### Environment Variables

```bash
POSTGRES_USER=postgres
POSTGRES_PASSWORD=postgres
POSTGRES_DB=postgres
```

### Connection Strings

**From Docker Network:**
```
postgresql://postgres:postgres@pgai-db:5432/ecoanp?sslmode=disable
```

**From Host Machine:**
```
postgresql://postgres:postgres@localhost:6543/ecoanp?sslmode=disable
```

### Ports

- **6543**: PostgreSQL/TimescaleDB (external)
- **5432**: PostgreSQL/TimescaleDB (internal)
- **11534**: Ollama AI (external)
- **11434**: Ollama AI (internal)

## 📊 Database Size

- **Database Size**: 626 MB (on disk)
- **Backup Size**: 25 MB (pg_dump custom format, compressed)
- **Current Records**: ~19,000 active records
- **Hypertables**: influx_hist (4 chunks, 1-hour partitions)
- **Continuous Aggregates**: 4 views (1m, 10m, 1h, 1d)
- **Largest Tables**:
  - alarm_vectors: 126 MB (pgvector embeddings)
  - _timescaledb_internal: 269 MB (chunks + metadata)
  - alarm_history: 5.7 MB

## 🛠️ Maintenance

### Create New Backup

```bash
# Custom format (recommended - 25MB compressed)
docker exec pgai-db pg_dump -U postgres -d ecoanp -F c -Z 9 > backup/ecoanp_backup_$(date +%Y%m%d).dump

# Plain SQL format (larger - ~90MB)
docker exec pgai-db pg_dump -U postgres -d ecoanp > backup/ecoanp_backup_$(date +%Y%m%d).sql

# Backup global objects (roles, etc.)
docker exec pgai-db pg_dumpall -U postgres --globals-only > backup/globals.sql
```

### Monitor Database

```bash
# Check connections
docker exec pgai-db psql -U postgres -d ecoanp -c "SELECT count(*) FROM pg_stat_activity WHERE datname = 'ecoanp'"

# Check database size
docker exec pgai-db psql -U postgres -d ecoanp -c "SELECT pg_size_pretty(pg_database_size('ecoanp'))"

# Check hypertable compression
docker exec pgai-db psql -U postgres -d ecoanp -c "SELECT * FROM timescaledb_information.compression_settings"
```

### View pg_cron Jobs

```bash
docker exec pgai-db psql -U postgres -d ecoanp -c "SELECT * FROM cron.job"

# Check job execution history
docker exec pgai-db psql -U postgres -d ecoanp -c "SELECT * FROM cron.job_run_details ORDER BY start_time DESC LIMIT 10"
```

## 🔒 Security

**⚠️ Production Deployment:**
1. Change default passwords
2. Enable SSL/TLS
3. Configure pg_hba.conf for network access
4. Set up backup automation
5. Enable TimescaleDB compression

## 📝 Migration Order

Apply migrations in this order:

1. **Virtual Tags** (01-08)
2. **Training Schema** (20251014_create_training_evaluation.sql)
3. **Forecast Cache** (20251017_create_forecast_player_cache.sql)

## 🐛 Troubleshooting

### Circular Foreign-Key Warnings

TimescaleDB hypertables have circular foreign-key constraints. This is expected behavior. Use `--disable-triggers` when restoring if needed.

### Connection Issues

```bash
# Check container health
docker ps | grep pgai-db

# View logs
docker logs pgai-db -f

# Restart container
docker-compose restart pgai-db
```

### Out of Connections

```bash
# Terminate idle connections
docker exec pgai-db psql -U postgres -d ecoanp -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = 'ecoanp' AND state = 'idle' AND pid <> pg_backend_pid()"
```

## 📚 Documentation

- [TimescaleDB Documentation](https://docs.timescale.com/)
- [pgai Documentation](https://github.com/timescale/pgai)
- [PostgreSQL pg_cron](https://github.com/citusdata/pg_cron)

## 📄 License

Part of Reflex-KSys SCADA system.
