CREATE ROLE yaml;

-- Because some data can
CREATE OR REPLACE FUNCTION cleanup_dump_data(IN from_role varchar)
    RETURNS varchar AS $$
DECLARE
    decom_from varchar := from_role || '_decom';
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = from_role) THEN
        EXECUTE 'ALTER ROLE ' || from_role || ' RENAME TO ' || decom_from || ';';
        EXECUTE 'DROP OWNED BY ' || decom_from || ';';
        EXECUTE 'DROP ROLE IF EXISTS ' || decom_from || ';';
    END IF;
    RETURN 'OK';
END
$$ LANGUAGE plpgsql;

-- Refining original fuzzwork including schema rename, filtering objects and creating missing indexes
CREATE OR REPLACE FUNCTION refine_dump_data(IN from_role varchar, IN to_schema varchar)
RETURNS varchar AS $$
DECLARE
    r pg_tables%rowtype;
    i int := 0;
BEGIN
    PERFORM cleanup_dump_data(to_schema);
    EXECUTE 'CREATE ROLE ' || to_schema || ';';
    EXECUTE 'CREATE SCHEMA ' || to_schema || ' AUTHORIZATION ' || to_schema || ';';
    FOR r IN
        SELECT * FROM pg_tables where tableowner = from_role
    LOOP
        EXECUTE 'ALTER TABLE ' || r.schemaname || '."' || r.tablename || '" SET SCHEMA ' || to_schema || ';';
        i := i + 1;
    END LOOP;
    EXECUTE 'REASSIGN OWNED BY ' || from_role || ' TO ' || to_schema || ';';
    RETURN i;
END
$$ LANGUAGE plpgsql;

