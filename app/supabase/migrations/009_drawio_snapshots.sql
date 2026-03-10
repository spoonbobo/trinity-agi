-- Migration 009: Persist DrawIO XML snapshots per user per OpenClaw

create table if not exists rbac.drawio_snapshots (
    id              uuid primary key default gen_random_uuid(),
    openclaw_id     uuid not null,
    user_id         uuid not null,
    name            text not null,
    xml             text not null,
    xml_hash        text not null,
    created_at      timestamptz not null default now(),
    updated_at      timestamptz not null default now(),
    unique (openclaw_id, user_id, xml_hash)
);

create index if not exists idx_drawio_snapshots_scope
    on rbac.drawio_snapshots (openclaw_id, user_id, updated_at desc);

create or replace function rbac.update_drawio_snapshots_timestamp()
returns trigger as $$
begin
    new.updated_at = now();
    return new;
end;
$$ language plpgsql;

drop trigger if exists trg_drawio_snapshots_updated_at on rbac.drawio_snapshots;
create trigger trg_drawio_snapshots_updated_at
    before update on rbac.drawio_snapshots
    for each row
    execute function rbac.update_drawio_snapshots_timestamp();
