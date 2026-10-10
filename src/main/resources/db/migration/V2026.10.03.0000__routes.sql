CREATE TABLE IF NOT EXISTS routes (
    origin_latitude DOUBLE PRECISION NOT NULL,
    origin_longitude DOUBLE PRECISION NOT NULL,
    destination_latitude DOUBLE PRECISION NOT NULL,
    destination_longitude DOUBLE PRECISION NOT NULL,
    estimate_time TIMESTAMP NOT NULL,
    duration BIGINT NOT NULL,
    static_duration BIGINT NOT NULL,
    distance INT NOT NULL,
    CONSTRAINT pk_routes PRIMARY KEY (estimate_time, origin_latitude, origin_longitude, destination_latitude, destination_longitude)
);
