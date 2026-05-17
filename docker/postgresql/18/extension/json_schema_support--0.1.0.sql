-- json_schema_support extension: JSON Schema validation registry
-- Requires: pg_jsonschema extension must be installed first
-- CREATE EXTENSION pg_jsonschema;
-- CREATE EXTENSION json_schema_support;

-- Schema registry table
CREATE TABLE IF NOT EXISTS json_schemas (
    schema_id       text PRIMARY KEY,
    schema_definition jsonb NOT NULL,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now()
);

-- Validation helper function
CREATE OR REPLACE FUNCTION validate_payload_against_registry(schema_key text, data_instance jsonb)
RETURNS boolean
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    target_schema json;
BEGIN
    SELECT schema_definition::json INTO target_schema
    FROM json_schemas
    WHERE schema_id = schema_key;

    IF target_schema IS NULL THEN
        RAISE EXCEPTION 'No schema found for key: %', schema_key;
    END IF;

    RETURN jsonb_matches_schema(target_schema, data_instance);
END;
$$;

-- Update trigger for updated_at
CREATE OR REPLACE FUNCTION json_schemas_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_trigger
        WHERE tgname = 'json_schemas_updated_at_trigger'
    ) THEN
        CREATE TRIGGER json_schemas_updated_at_trigger
            BEFORE UPDATE ON json_schemas
            FOR EACH ROW
            EXECUTE FUNCTION json_schemas_updated_at();
    END IF;
END;
$$;

-- Helper function: add a dynamic JSON schema check constraint to any table
-- Usage examples:
--   SELECT add_json_schema_check('user_payloads', 'schema_id', 'payload');
--   SELECT add_json_schema_check('user_payloads', 'schema_id', 'payload', 'analytics');
-- This is equivalent to:
--   ALTER TABLE user_payloads
--   ADD CONSTRAINT json_schema_check_user_payloads
--   CHECK (payload::json IS NOT NULL AND validate_payload_against_registry(schema_id, payload));
CREATE OR REPLACE FUNCTION add_json_schema_check(
    in_table_name TEXT,
    in_schema_col TEXT,
    in_payload_col TEXT,
    IN in_schema_name TEXT DEFAULT 'public'
) RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    full_table TEXT;
    constraint_name TEXT;
    col_type TEXT;
BEGIN
    -- Build the fully qualified table name
    full_table := format('%I.%I', in_schema_name, in_table_name);

    -- Get the column type
    SELECT data_type INTO col_type
    FROM information_schema.columns
    WHERE table_schema = in_schema_name
      AND table_name = in_table_name
      AND column_name = in_payload_col;

    IF col_type != 'jsonb' THEN
        RAISE EXCEPTION 'Column "%" on table "%" is not a jsonb column (found: %)',
            in_payload_col, full_table, COALESCE(col_type, 'NULL (column does not exist)');
    END IF;

    -- Check if constraint already exists
    SELECT conname INTO constraint_name
    FROM pg_constraint
    WHERE conrelid = full_table::regclass
      AND contype = 'c'
      AND conname = 'json_schema_check_' || in_table_name;

    IF constraint_name IS NOT NULL THEN
        RAISE WARNING 'Constraint "json_schema_check_%" already exists on table %', in_table_name, full_table;
        RETURN;
    END IF;

    -- Add the check constraint
    EXECUTE format(
        'ALTER TABLE %s ADD CONSTRAINT %I CHECK (%I::json IS NOT NULL AND validate_payload_against_registry(%I, %I))',
        full_table,
        'json_schema_check_' || in_table_name,
        in_payload_col,
        in_schema_col,
        in_payload_col
    );
END;
$$;
