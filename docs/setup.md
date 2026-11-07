# Setup Notes

Project: E-commerce Customer Retention & RFM (SQL Server)
Task: E0-06 (memory, file locations and disk). The rest of the setup guide is added in E15.

---

## 1. Memory budget

The PC has **16 GB of RAM**. Memory is limited at four levels, and the smallest limit is the one that applies:

| Level | Setting | Value |
|---|---|---|
| Windows (the PC) | Installed RAM | 16 GB |
| WSL2 virtual machine (Docker's engine) | `memory` in `%USERPROFILE%\.wslconfig` | **10 GB** (default without the file: about half of the RAM, 7.8 GB was seen) |
| Container | none | Inherits the WSL2 limit |
| SQL Server | `MSSQL_MEMORY_LIMIT_MB` in `docker-compose.yml` | **8192 MB** (was 4096 MB) |

| Part of the budget | Size | Notes |
|---|---|---|
| Windows, SSMS, browser, editor, Notion | about 6 GB | Heavy tools such as Power BI Desktop (Part 2) are closed during big loads |
| WSL2 virtual machine | 10 GB | A cap, not a reservation: unused memory is available to Windows |
| of which SQL Server | 8 GB | About 80% of the machine, which leaves room for the Linux system and non-buffer memory |

**Why these values.** The first estimate of the table sizes (about 19 GB for bronze) is larger than any memory we can give, so queries will read from disk anyway. More memory means fewer spills to `tempdb` and faster scans, but giving SQL Server everything would starve Windows and slow the whole PC.

### Configuration

`%USERPROFILE%\.wslconfig`:
```
[wsl2]
memory=10GB
```

`docker-compose.yml`, in the `environment` section of the SQL Server service:
```yaml
MSSQL_MEMORY_LIMIT_MB: "8192"
```

Applying the change: `wsl --shutdown`, restart Docker Desktop, then `docker compose up -d`. The container is recreated, and the data volume is kept.

### How to check

```powershell
docker exec rfm-sqlserver sh -c "free -m"
```
```sql
SELECT
    physical_memory_kb / 1024 AS visible_memory_mb,
    committed_target_kb / 1024 AS sql_target_mb
FROM sys.dm_os_sys_info;
```

| Check | Before | After |
|---|---|---|
| Memory seen by the container (`free -m`, total) | 7,793 MB | **9,945 MB** |
| Memory available to programs (`free -m`, available) | 6,034 MB | **8,474 MB** |
| Memory seen by SQL Server (`visible_memory_mb`) | not measured (limit 4,096 MB) | **8,192 MB**, equal to `MSSQL_MEMORY_LIMIT_MB` |
| Target memory of SQL Server (`sql_target_mb`) | not measured | **7,281 MB** |
| Databases after the container was recreated | | `ecommerce_rfm_raw` and `ecommerce_rfm_dwh` both present |
| Container status | | healthy |

**Reading the results.** The virtual machine took the 10 GB limit, and SQL Server took the 8 GB limit. The target (7,281 MB) is below the limit because SQL Server keeps part of the limit for memory that is not counted in the target (for example thread stacks), so it is normal for the target to be lower. The memory to watch during loads is `available` in `free -m`.

### Going back

Delete `%USERPROFILE%\.wslconfig`, set `MSSQL_MEMORY_LIMIT_MB` back to `4096`, then run the same steps to apply.

---

## 2. Disk

| Item | Value |
|---|---|
| Free space on `C:` | 212.83 GB when measured |
| Space needed at the peak | about 75 to 100 GB (see `data_sources.md`, storage plan) |
| Minimum free space | 60 GB. Below it, stop loading and clean up |
| Check Docker's disk use | `docker system df` |

---

## 3. File locations

| Data | Location |
|---|---|
| Source CSV files | `data\raw\rees46\` in the repository (mounted read-only as `/data/raw/rees46`) |
| Database data and log files | Docker volume `ecommerce-retention-rfm-sqlserver_sqlserver_data`, mounted at `/var/opt/mssql` in the container |
| `tempdb` | Same volume, default location |
| Backups | To be written to a folder outside the Docker volume, so that losing the volume does not lose the backups (task E9) |

**Never delete the volume** (`docker compose down -v` or the delete button in Docker Desktop). It holds the databases.
