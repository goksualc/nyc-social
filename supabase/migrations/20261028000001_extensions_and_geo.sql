-- Along · migration 1 — extensions, private schema, Manhattan geography helpers
-- Everything in the `private` schema is NOT exposed through the Data API (PostgREST only exposes `public`).

create extension if not exists postgis with schema extensions;

create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to authenticated;   -- needed so RLS policies can call private helpers

create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

-- ---------------------------------------------------------------------------
-- Manhattan boundary (EPSG:4326). A loose outline of the island, slightly generous around waterfront parks.
-- Mirrors `ManhattanGeo.boundary` in the iOS app; the server is the authority.
-- ---------------------------------------------------------------------------
create table private.geo_regions (
  name     text primary key,
  boundary extensions.geometry(Polygon, 4326) not null
);
alter table private.geo_regions enable row level security;   -- no policies: unreachable except via definer functions
create index geo_regions_boundary_gix on private.geo_regions using gist (boundary);

insert into private.geo_regions (name, boundary) values (
  'manhattan',
  extensions.ST_GeomFromText('POLYGON((
    -74.0200 40.6990, -74.0210 40.7150, -74.0150 40.7300, -74.0100 40.7450, -74.0030 40.7600,
    -73.9970 40.7720, -73.9890 40.7900, -73.9780 40.8050, -73.9660 40.8200, -73.9520 40.8350,
    -73.9420 40.8500, -73.9310 40.8620, -73.9220 40.8760, -73.9100 40.8830, -73.9250 40.8480,
    -73.9290 40.8250, -73.9270 40.8100, -73.9280 40.7990, -73.9370 40.7900, -73.9450 40.7750,
    -73.9540 40.7600, -73.9670 40.7450, -73.9710 40.7300, -73.9730 40.7200, -73.9760 40.7120,
    -73.9910 40.7090, -73.9990 40.7050, -74.0080 40.7000, -74.0200 40.6990
  ))', 4326)
);

create or replace function private.is_in_manhattan(p_lng double precision, p_lat double precision)
returns boolean language sql stable security definer set search_path = public, extensions as $$
  select exists (
    select 1 from private.geo_regions r
    where r.name = 'manhattan'
      and ST_Covers(r.boundary, ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326))
  )
$$;

-- Within `p_meters` of the island outline: used for route vertices so riverside greenways aren't rejected by the
-- deliberately rough polygon, while routes that wander off to New Jersey or Brooklyn still are.
create or replace function private.is_near_manhattan(p_lng double precision, p_lat double precision, p_meters double precision default 400)
returns boolean language sql stable security definer set search_path = public, extensions as $$
  select exists (
    select 1 from private.geo_regions r
    where r.name = 'manhattan'
      and ST_DWithin(r.boundary::geography, ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography, p_meters)
  )
$$;

-- ---------------------------------------------------------------------------
-- Neighbourhoods: the server derives the public "area" label itself instead of trusting the client.
-- ---------------------------------------------------------------------------
create table private.neighborhoods (
  name     text primary key,
  centroid extensions.geography(Point, 4326) not null
);
alter table private.neighborhoods enable row level security;
create index neighborhoods_centroid_gix on private.neighborhoods using gist (centroid);

insert into private.neighborhoods (name, centroid)
select n, extensions.ST_SetSRID(extensions.ST_MakePoint(lng, lat), 4326)::extensions.geography
from (values
  ('Financial District', -74.0090, 40.7075), ('Tribeca', -74.0089, 40.7195), ('Chinatown', -73.9970, 40.7158),
  ('SoHo', -74.0030, 40.7233), ('Lower East Side', -73.9843, 40.7150), ('East Village', -73.9815, 40.7265),
  ('West Village', -74.0036, 40.7358), ('Greenwich Village', -73.9990, 40.7336), ('Chelsea', -74.0014, 40.7465),
  ('Flatiron', -73.9897, 40.7411), ('Gramercy', -73.9845, 40.7368), ('Murray Hill', -73.9757, 40.7479),
  ('Hell''s Kitchen', -73.9918, 40.7638), ('Midtown', -73.9840, 40.7549), ('Midtown East', -73.9700, 40.7553),
  ('Lincoln Square', -73.9840, 40.7737), ('Upper West Side', -73.9754, 40.7870), ('Upper East Side', -73.9566, 40.7736),
  ('Central Park', -73.9654, 40.7829), ('Morningside Heights', -73.9626, 40.8100), ('Harlem', -73.9465, 40.8116),
  ('Washington Heights', -73.9393, 40.8417), ('Inwood', -73.9212, 40.8677)
) as t(n, lng, lat);

create or replace function private.nearest_neighborhood(p_point extensions.geography)
returns text language sql stable security definer set search_path = public, extensions as $$
  select n.name from private.neighborhoods n order by n.centroid <-> p_point limit 1
$$;

-- Public locations are snapped to a coarse grid (~250 m). Same grid as the iOS client's `Coordinate.approximate`.
create or replace function private.snap_to_public_grid(p_point extensions.geography)
returns extensions.geography language sql immutable set search_path = public, extensions as $$
  select ST_SetSRID(ST_MakePoint(
           round(ST_X(p_point::geometry) / 0.0030) * 0.0030,
           round(ST_Y(p_point::geometry) / 0.0025) * 0.0025), 4326)::geography
$$;
