CREATE TABLE esi_call_history(
                                 resource_key character varying(1000) NOT NULL,
                                 operation_id character varying(200) NOT NULL,
                                 etag character varying(128),
                                 esi_request_id character varying(128) NOT NULL,
                                 error_limit_remaining integer NOT NULL,
                                 error_limit_reset integer NOT NULL,
                                 status integer NOT NULL,
                                 expires timestamp NOT NULL,
                                 logged timestamp NOT NULL DEFAULT current_timestamp
);
ALTER TABLE esi_call_history OWNER TO esi;
GRANT SELECT ON TABLE esi_call_history to authenticated;
GRANT INSERT ON TABLE esi_call_history to authenticated;
