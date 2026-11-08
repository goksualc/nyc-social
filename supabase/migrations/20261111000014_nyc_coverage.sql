-- Along · migration 14 — all five boroughs
--
-- Walks may now start, end and run anywhere in New York City. Nothing deployed is edited: this adds boundary rows and
-- neighbourhood labels, then redefines the two private helpers that every create/route RPC already calls
-- (`is_in_manhattan`, `is_near_manhattan`) so that they test against the whole city instead of the island alone.
-- The names are kept on purpose: the RPC bodies (and the `outside_manhattan` error code the app already understands)
-- stay byte-for-byte as deployed. Existing Manhattan walks are untouched.
--
-- BOUNDARIES: hand-traced outlines of each borough's land and near-shore water, not survey data. Along the water they
-- run a few hundred metres off the shore (so waterfront parks, piers and greenways validate); on the land borders
-- (Nassau, Westchester, New Jersey) they follow the city line. Replace the five polygons with an official NYC Open Data
-- "Borough Boundaries" extract if you need survey-grade edges: only the rows below change, no function does.

insert into private.geo_regions (name, boundary) values
('nyc_bronx', extensions.ST_GeomFromText('POLYGON((
  -73.9350 40.8000, -73.9300 40.8300, -73.9300 40.8650, -73.9300 40.8780, -73.9270 40.9000, -73.9200 40.9170,
  -73.8600 40.9150, -73.8100 40.8990, -73.7850 40.8900, -73.7700 40.8700, -73.7700 40.8400, -73.7850 40.8070,
  -73.8300 40.7990, -73.8800 40.7960, -73.9200 40.7930, -73.9350 40.8000))', 4326)),
('nyc_queens', extensions.ST_GeomFromText('POLYGON((
  -73.9650 40.7300, -73.9600 40.7450, -73.9500 40.7560, -73.9420 40.7700, -73.9300 40.7830, -73.9150 40.7900,
  -73.9000 40.7880, -73.8800 40.7850, -73.8500 40.7900, -73.8300 40.7930, -73.8000 40.7960, -73.7700 40.7870, -73.7400 40.7720,
  -73.7000 40.7520, -73.7000 40.7250, -73.7150 40.7050, -73.7260 40.6900, -73.7400 40.6650, -73.7380 40.6050,
  -73.7300 40.5900, -73.7500 40.5820, -73.8500 40.5680, -73.9400 40.5530, -73.9420 40.5680, -73.9050 40.5850,
  -73.8950 40.6000, -73.8600 40.6700, -73.8950 40.6950, -73.9300 40.7060, -73.9650 40.7300))', 4326)),
('nyc_brooklyn', extensions.ST_GeomFromText('POLYGON((
  -73.9650 40.7250, -73.9600 40.7450, -73.9250 40.7300, -73.8950 40.6960, -73.8550 40.6770, -73.8500 40.6500,
  -73.8700 40.6100, -73.8900 40.5880, -73.9000 40.5650, -73.9800 40.5560, -74.0450 40.5650, -74.0450 40.6050,
  -74.0450 40.6350, -74.0250 40.6600, -74.0150 40.6850, -74.0080 40.6990, -73.9980 40.7100, -73.9800 40.7160,
  -73.9650 40.7250))', 4326)),
('nyc_staten_island', extensions.ST_GeomFromText('POLYGON((
  -74.0750 40.6600, -74.0500 40.6150, -74.0500 40.5950, -74.0600 40.5900, -74.0900 40.5550, -74.1500 40.5350,
  -74.2000 40.5050, -74.2600 40.4850, -74.2600 40.5200, -74.2400 40.5400, -74.2000 40.5800, -74.1900 40.6300,
  -74.1600 40.6450, -74.1300 40.6450, -74.1000 40.6500, -74.0750 40.6600))', 4326));

-- The one definition of "in the city": inside any of the five outlines (the Manhattan row is the one from migration 1).
create or replace function private.is_in_nyc(p_lng double precision, p_lat double precision)
returns boolean language sql stable security definer set search_path = public, extensions as $$
  select exists (
    select 1 from private.geo_regions r
    where r.name in ('manhattan', 'nyc_bronx', 'nyc_queens', 'nyc_brooklyn', 'nyc_staten_island')
      and ST_Covers(r.boundary, ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326))
  )
$$;

create or replace function private.is_near_nyc(p_lng double precision, p_lat double precision, p_meters double precision default 400)
returns boolean language sql stable security definer set search_path = public, extensions as $$
  select exists (
    select 1 from private.geo_regions r
    where r.name in ('manhattan', 'nyc_bronx', 'nyc_queens', 'nyc_brooklyn', 'nyc_staten_island')
      and ST_DWithin(r.boundary::geography, ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography, p_meters)
  )
$$;

-- Deployed RPCs call these two names; they now mean "New York City".
create or replace function private.is_in_manhattan(p_lng double precision, p_lat double precision)
returns boolean language sql stable security definer set search_path = public, extensions as $$
  select private.is_in_nyc(p_lng, p_lat)
$$;
create or replace function private.is_near_manhattan(p_lng double precision, p_lat double precision, p_meters double precision default 400)
returns boolean language sql stable security definer set search_path = public, extensions as $$
  select private.is_near_nyc(p_lng, p_lat, p_meters)
$$;

-- Public area labels ("Williamsburg", "Flushing", …) come from the nearest neighbourhood centroid.
insert into private.neighborhoods (name, centroid)
select n, extensions.ST_SetSRID(extensions.ST_MakePoint(lng, lat), 4326)::extensions.geography
from (values
  ('Williamsburg', -73.9571, 40.7081), ('Greenpoint', -73.9515, 40.7304), ('DUMBO', -73.9890, 40.7033),
  ('Brooklyn Heights', -73.9936, 40.6960), ('Park Slope', -73.9814, 40.6710), ('Prospect Park', -73.9690, 40.6602),
  ('Bushwick', -73.9213, 40.6944), ('Bed-Stuy', -73.9418, 40.6872), ('Crown Heights', -73.9442, 40.6694),
  ('Coney Island', -73.9707, 40.5755), ('Bay Ridge', -74.0299, 40.6264), ('Sunset Park', -74.0124, 40.6453),
  ('Red Hook', -74.0083, 40.6734), ('Brighton Beach', -73.9617, 40.5776), ('Flatbush', -73.9594, 40.6409),
  ('Astoria', -73.9235, 40.7644), ('Long Island City', -73.9485, 40.7447), ('Flushing', -73.8331, 40.7675),
  ('Jackson Heights', -73.8831, 40.7557), ('Forest Hills', -73.8448, 40.7185), ('Jamaica', -73.7890, 40.7027),
  ('Rockaway Beach', -73.8160, 40.5834), ('Sunnyside', -73.9196, 40.7433), ('Flushing Meadows', -73.8408, 40.7466),
  ('Bayside', -73.7771, 40.7686), ('Ridgewood', -73.9018, 40.7043),
  ('Riverdale', -73.9140, 40.8910), ('Fordham', -73.8900, 40.8610), ('Belmont', -73.8880, 40.8546),
  ('Pelham Bay', -73.8280, 40.8528), ('Kingsbridge', -73.9020, 40.8815), ('Concourse', -73.9262, 40.8296),
  ('Bronx Zoo', -73.8770, 40.8506), ('City Island', -73.7864, 40.8468), ('Hunts Point', -73.8800, 40.8130),
  ('Mott Haven', -73.9229, 40.8090),
  ('St. George', -74.0735, 40.6437), ('Stapleton', -74.0770, 40.6270), ('Great Kills', -74.1510, 40.5540),
  ('Tottenville', -74.2430, 40.5080), ('New Dorp', -74.1160, 40.5740), ('Port Richmond', -74.1370, 40.6350),
  ('Snug Harbor', -74.1020, 40.6445), ('Todt Hill', -74.1100, 40.5950)
) as t(n, lng, lat)
on conflict (name) do nothing;
