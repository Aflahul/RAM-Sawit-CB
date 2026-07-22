param(
  [string]$Container = 'supabase_db_RAM-Sawit-CB'
)

$ErrorActionPreference = 'Stop'

if ($Container -notmatch '^supabase_db_[A-Za-z0-9_.-]+$') {
  throw 'Safety stop: container name must identify a Supabase local database container.'
}

function Invoke-Docker {
  param([Parameter(Mandatory)][string[]]$Arguments)

  $output = & docker @Arguments 2>&1
  if ($LASTEXITCODE -ne 0) {
    throw "Docker command failed: $($output -join [Environment]::NewLine)"
  }
  return $output
}

function Test-DatabaseExists {
  param([Parameter(Mandatory)][string]$Database)

  $result = Invoke-Docker @(
    'exec', $Container, 'psql', '-U', 'postgres', '-d', 'postgres', '-Atc',
    "select 1 from pg_database where datname='$Database'"
  )
  return ($result -join '').Trim() -eq '1'
}

function Initialize-TargetDatabase {
  param(
    [Parameter(Mandatory)][string]$Database,
    [Parameter(Mandatory)][string]$BaseDump
  )

  Invoke-Docker @('exec', $Container, 'createdb', '-U', 'postgres', $Database) | Out-Null
  Invoke-Docker @('exec', $Container, 'psql', '-U', 'postgres', '-d', $Database, '-v', 'ON_ERROR_STOP=1', '-c', 'drop schema public cascade') | Out-Null
  Invoke-Docker @('exec', $Container, 'psql', '-U', 'postgres', '-d', $Database, '-v', 'ON_ERROR_STOP=1', '-c', 'create schema extensions') | Out-Null
  Invoke-Docker @('exec', $Container, 'psql', '-U', 'postgres', '-d', $Database, '-v', 'ON_ERROR_STOP=1', '-c', 'create extension btree_gist with schema extensions') | Out-Null
  Invoke-Docker @('exec', $Container, 'psql', '-U', 'postgres', '-d', $Database, '-v', 'ON_ERROR_STOP=1', '-c', 'create extension pgcrypto with schema extensions') | Out-Null
  Invoke-Docker @('exec', $Container, 'pg_restore', '-U', 'postgres', '-d', $Database, '--no-owner', '--no-acl', '--exit-on-error', $BaseDump) | Out-Null
}

function Get-AuditSignature {
  param([Parameter(Mandatory)][string]$Database)

  $sql = "select count(*)::text || '|' || md5(coalesce(string_agg(row_to_json(t)::text, '' order by id), '')) from public.audit_log t"
  return ((Invoke-Docker @('exec', $Container, 'psql', '-U', 'postgres', '-d', $Database, '-Atc', $sql)) -join '').Trim()
}

$running = ((Invoke-Docker @('inspect', '--format', '{{.State.Running}}', $Container)) -join '').Trim()
if ($running -ne 'true') {
  throw "Safety stop: container $Container is not running."
}

$suffix = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$sourceDatabase = "restore_drill_source_$suffix"
$targetDatabase = "restore_drill_target_$suffix"
$baseDump = "/tmp/restore_drill_base_$suffix.dump"
$auditDump = "/tmp/restore_drill_audit_$suffix.dump"
$startedAt = [DateTimeOffset]::UtcNow

foreach ($database in @($sourceDatabase, $targetDatabase)) {
  if ($database -notmatch '^restore_drill_(source|target)_\d+$') {
    throw "Safety stop: invalid temporary database name $database."
  }
  if (Test-DatabaseExists $database) {
    throw "Safety stop: temporary database $database already exists."
  }
}

try {
  Invoke-Docker @(
    'exec', $Container, 'pg_dump', '-U', 'postgres', '-d', 'postgres', '-Fc',
    '--no-owner', '--no-acl', '-n', 'public', '-n', 'auth', '-n', 'storage',
    '-n', 'graphql_public', '-f', $baseDump
  ) | Out-Null

  Initialize-TargetDatabase -Database $sourceDatabase -BaseDump $baseDump
  Initialize-TargetDatabase -Database $targetDatabase -BaseDump $baseDump

  $fixtureSql = @"
alter table public.audit_log disable trigger guard_audit_log_insert;
insert into public.audit_log (entity_type, action, after_json, alasan)
values ('restore_drill', 'create', jsonb_build_object('fixture', true), 'synthetic local restore drill');
alter table public.audit_log enable trigger guard_audit_log_insert;
"@
  Invoke-Docker @('exec', $Container, 'psql', '-U', 'postgres', '-d', $sourceDatabase, '-v', 'ON_ERROR_STOP=1', '-c', $fixtureSql) | Out-Null

  $sourceSignature = Get-AuditSignature $sourceDatabase

  Invoke-Docker @(
    'exec', $Container, 'pg_dump', '-U', 'postgres', '-d', $sourceDatabase,
    '-Fc', '--data-only', '--no-owner', '--no-acl', '-t', 'public.audit_log',
    '-f', $auditDump
  ) | Out-Null

  Invoke-Docker @('exec', $Container, 'psql', '-U', 'postgres', '-d', $targetDatabase, '-v', 'ON_ERROR_STOP=1', '-c', 'alter table public.audit_log disable trigger guard_audit_log_insert') | Out-Null
  Invoke-Docker @('exec', $Container, 'pg_restore', '-U', 'postgres', '-d', $targetDatabase, '--data-only', '--no-owner', '--no-acl', '--exit-on-error', $auditDump) | Out-Null
  Invoke-Docker @('exec', $Container, 'psql', '-U', 'postgres', '-d', $targetDatabase, '-v', 'ON_ERROR_STOP=1', '-c', 'alter table public.audit_log enable trigger guard_audit_log_insert') | Out-Null

  $targetSignature = Get-AuditSignature $targetDatabase
  if ($sourceSignature -ne $targetSignature) {
    throw "Restore reconciliation failed: source=$sourceSignature target=$targetSignature"
  }

  $triggerState = ((Invoke-Docker @(
    'exec', $Container, 'psql', '-U', 'postgres', '-d', $targetDatabase, '-Atc',
    "select string_agg(tgname || ':' || tgenabled::text, ',' order by tgname) from pg_trigger where tgrelid='public.audit_log'::regclass and not tgisinternal"
  )) -join '').Trim()

  $previousErrorAction = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  $negativeOutput = & docker exec $Container psql -U postgres -d $targetDatabase -v ON_ERROR_STOP=1 -c 'update public.audit_log set alasan = ''mutation must fail''' 2>$null
  $negativeExit = $LASTEXITCODE
  $ErrorActionPreference = $previousErrorAction
  if ($negativeExit -eq 0) {
    throw 'Negative mutation test unexpectedly succeeded.'
  }

  [pscustomobject]@{
    status = 'PASS'
    scope = 'local logical restore of public/auth/storage plus audit-log reconciliation'
    source_signature = $sourceSignature
    target_signature = $targetSignature
    trigger_state = $triggerState
    mutation_denied = $true
    started_at_utc = $startedAt.ToString('o')
    finished_at_utc = [DateTimeOffset]::UtcNow.ToString('o')
    duration_seconds = [math]::Round(([DateTimeOffset]::UtcNow - $startedAt).TotalSeconds, 2)
  } | ConvertTo-Json -Compress
}
finally {
  foreach ($database in @($sourceDatabase, $targetDatabase)) {
    if ($database -match '^restore_drill_(source|target)_\d+$' -and (Test-DatabaseExists $database)) {
      Invoke-Docker @('exec', $Container, 'dropdb', '-U', 'postgres', $database) | Out-Null
    }
  }
  Invoke-Docker @('exec', $Container, 'rm', '-f', $baseDump, $auditDump) | Out-Null
}
