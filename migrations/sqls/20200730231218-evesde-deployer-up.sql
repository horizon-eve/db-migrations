
CREATE TABLE EVESDE_UPGRADE_HISTORY (
    MD5 varchar not null,
    UPGRADED timestamp not null default CURRENT_TIMESTAMP
);

CREATE OR REPLACE FUNCTION is_upgrade_needed(IN for_md5 varchar)
    RETURNS varchar as $$
DECLARE
    latest_md5 varchar;
BEGIN
    select MD5 into latest_md5
    from EVESDE_UPGRADE_HISTORY
    order by UPGRADED desc
    limit 1;
    if for_md5 = latest_md5 then
        return 'no';
    end if;
    return 'yes';
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION preimport_evesde(IN intake_schema varchar)
    RETURNS varchar AS $$
BEGIN
    EXECUTE 'DROP SCHEMA IF EXISTS ' || intake_schema || ' CASCADE;';
    EXECUTE 'DROP ROLE IF EXISTS ' || intake_schema || ';';
    EXECUTE 'CREATE ROLE ' || intake_schema || ';';
    RETURN 'OK';
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION activate_evesde(IN intake_schema varchar, IN md5 varchar)
    RETURNS varchar AS $$
BEGIN
    IF EXISTS(
            SELECT schema_name
            FROM information_schema.schemata
            WHERE schema_name = 'evesde'
        )
    THEN
        ALTER SCHEMA evesde RENAME TO evesde_decom;
        ALTER ROLE evesde RENAME TO evesde_decom;
    END IF;

    EXECUTE 'ALTER ROLE ' || intake_schema || ' RENAME TO evesde;';
    EXECUTE 'ALTER SCHEMA ' || intake_schema || ' RENAME TO evesde;';
    ALTER SCHEMA evesde OWNER TO evesde;
    -- Refresh memberships
    GRANT SELECT ON ALL TABLES IN SCHEMA evesde TO api;
    GRANT USAGE ON SCHEMA evesde TO api;

    IF EXISTS(
            SELECT schema_name
            FROM information_schema.schemata
            WHERE schema_name = 'evesde_decom'
        )
    THEN
        -- Reassign views -- !!! THIS IS A VERY BAD IDEA!!! because it is going to kill my db for sure, oh poor db
        UPDATE pg_depend ud
        SET refobjid = att.attrelid, refobjsubid = att.attnum
        FROM pg_depend d
                 JOIN pg_class refobj on d.refobjid = refobj.oid
                 JOIN pg_attribute refatt on refatt.attrelid = refobj.oid
            AND refatt.attnum = d.refobjsubid
                 JOIN pg_namespace refobjns on refobjns.oid = refobj.relnamespace
                 JOIN pg_rewrite rw on rw.oid = d.objid
                 JOIN pg_class rc on rc.oid = rw.ev_class
                 JOIN pg_class rel on rel.relname = refobj.relname
                 JOIN pg_attribute att on att.attrelid = rel.oid
            AND att.attname = refatt.attname
                 JOIN pg_namespace relns on relns.oid = rel.relnamespace
        WHERE ud.classid = d.classid
          AND ud.objid = d.objid
          AND ud.objsubid = d.objsubid
          AND ud.deptype = d.deptype
          AND rc.relnamespace != refobjns.oid
          AND refobjns.nspname = 'evesde_decom'
          AND relns.nspname ='evesde';

        DROP SCHEMA evesde_decom CASCADE;
        DROP ROLE evesde_decom;
    END IF;
    INSERT INTO EVESDE_UPGRADE_HISTORY(md5) VALUES (md5);
    RETURN 'OK';
END
$$ LANGUAGE plpgsql;
