-- ============================================================
--  PRODUCT BOX SIZE — one-time database setup.
--  Run this whole file once in Supabase → SQL Editor → New query.
--  Re-running it is safe: nothing is dropped, nothing is doubled.
-- ============================================================

create table if not exists public.pbs_products (
  id bigint generated always as identity primary key,
  name text not null,
  unit_weight numeric,
  fba_unit integer,
  item_dimension text,
  item_box_dimension text,
  notes text,
  image_url text,
  created_at timestamptz not null default now()
);
alter table public.pbs_products add column if not exists image_url text;
create unique index if not exists pbs_products_name_key on public.pbs_products (lower(name));

create table if not exists public.pbs_boxes (
  id bigint generated always as identity primary key,
  product_id bigint not null references public.pbs_products(id) on delete cascade,
  box_dimension text,
  unit_in_box integer,
  sort_order integer not null default 0
);
create index if not exists pbs_boxes_product_idx on public.pbs_boxes (product_id, sort_order);

create table if not exists public.pbs_bags (
  id bigint generated always as identity primary key,
  code text not null,
  product text,
  sort_order integer not null default 0
);

create table if not exists public.pbs_deleted_items (
  id bigint generated always as identity primary key,
  table_name text not null,
  row_data jsonb not null,
  summary text,
  deleted_at timestamptz not null default now()
);

alter table public.pbs_products      enable row level security;
alter table public.pbs_boxes         enable row level security;
alter table public.pbs_bags          enable row level security;
alter table public.pbs_deleted_items enable row level security;

-- The app ships with the public (anon) key, so these four tables are
-- readable and writable by anyone who has the app link. That is the same
-- exposure the shared spreadsheet had. Keep the link inside the team.
do $$
declare t text;
begin
  foreach t in array array['pbs_products','pbs_boxes','pbs_bags','pbs_deleted_items'] loop
    execute format('drop policy if exists %I on public.%I', t||'_read', t);
    execute format('drop policy if exists %I on public.%I', t||'_write', t);
    execute format('create policy %I on public.%I for select to anon, authenticated using (true)', t||'_read', t);
    execute format('create policy %I on public.%I for all to anon, authenticated using (true) with check (true)', t||'_write', t);
  end loop;
end $$;

-- Product photos live in a public storage bucket.
insert into storage.buckets (id, name, public) values ('pbs-images','pbs-images', true)
on conflict (id) do update set public = true;

drop policy if exists pbs_images_read  on storage.objects;
drop policy if exists pbs_images_write on storage.objects;
create policy pbs_images_read  on storage.objects for select to anon, authenticated using (bucket_id = 'pbs-images');
create policy pbs_images_write on storage.objects for all to anon, authenticated using (bucket_id = 'pbs-images') with check (bucket_id = 'pbs-images');

-- ============================================================
--  SEED — the 192 products and 6 bag sizes exactly as they are
--  in "Product Box Dimension (3-9-26).xlsm". Blank cells in the
--  sheet stay blank here; nothing is guessed or filled in.
--  Safe to re-run: it does nothing if products already exist.
-- ============================================================
do $$
begin
  if exists (select 1 from public.pbs_products limit 1) then
    raise notice 'pbs_products already has rows — seed skipped.';
    return;
  end if;

  with src(name, unit_weight, fba_unit, item_dimension, item_box_dimension, notes, boxes) as (values
    ('10.1 Frame',0.712,null,null,'13x9x2',null,array[jsonb_build_object('d','32x48x39','u',20)]::jsonb[]),
    ('1002T Amplifier',0.168,null,null,'Regular (7x4x2)',null,array[jsonb_build_object('d','27x26x43','u',50)]::jsonb[]),
    ('10A-Handheld Car Battery',1.012,null,null,'9.5x7x5.5',null,array[jsonb_build_object('d','36x45x45','u',16)]::jsonb[]),
    ('15.6 Frame',1.669,null,'19.5x11x2.5',null,null,array[jsonb_build_object('d','31x52x58','u',10)]::jsonb[]),
    ('15A Car Battery',0.84,null,null,'10x3x7',null,array[jsonb_build_object('d','37x40x42','u',20)]::jsonb[]),
    ('20A Car Battery',0.83,null,null,'10x3x7',null,array[jsonb_build_object('d','32x35x36','u',20)]::jsonb[]),
    ('4-Pet Groom Kit',0.34,null,null,null,null,array[jsonb_build_object('d','22x26x45','u',50)]::jsonb[]),
    ('5-Pet Groom Kit',0.42,null,null,null,null,array[jsonb_build_object('d','22x26x45','u',50)]::jsonb[]),
    ('6 Button EMF Meter',0.231,null,null,'Regular (7x4x2)',null,array[]::jsonb[]),
    ('63A Voltage Protector',0.1,null,null,'Regular (7x4x2)',null,array[jsonb_build_object('d','18x20x33','u',100)]::jsonb[]),
    ('9x9 Heat Press',3.52,null,null,'FBA',null,array[jsonb_build_object('d','34x34x60','u',4)]::jsonb[]),
    ('AK35 Amplifier',0.58,null,null,'9x9x3',null,array[jsonb_build_object('d','29x42x73','u',40), jsonb_build_object('d','30x42x58','u',30)]::jsonb[]),
    ('AK45 Amplifier',0.93,null,null,'12x9.5x4',null,array[jsonb_build_object('d','42x40x47','u',16), jsonb_build_object('d','24x30x32','u',4)]::jsonb[]),
    ('Amplifier Module',0.24,null,null,'8x5x2.5',null,array[jsonb_build_object('d','28x29x59','u',50)]::jsonb[]),
    ('ANENG Megohm Meter',0.97,null,null,'9x9x3',null,array[jsonb_build_object('d','45x46x49','u',16), jsonb_build_object('d','31x41x47','u',12), jsonb_build_object('d','23x35x45','u',6)]::jsonb[]),
    ('ANENG Multimeter',0.44,null,null,'8x5x2.5',null,array[jsonb_build_object('d','36x40x47','u',50)]::jsonb[]),
    ('Angle Finder',null,null,null,null,null,array[jsonb_build_object('d','20x30x30','u',50)]::jsonb[]),
    ('Artecho-100 Pcs',0.5,null,null,null,null,array[jsonb_build_object('d','20x25x39','u',25)]::jsonb[]),
    ('AS-22 Amplifier',0.63,null,null,'9x9x3',null,array[jsonb_build_object('d','38x38x49','u',20)]::jsonb[]),
    ('Auto Transfer Switch',1.211,null,null,'9.5x7x5.5',null,array[jsonb_build_object('d','27x35x44','u',12)]::jsonb[]),
    ('Battery Switch',0.203,null,null,'Regular (7x4x2)',null,array[jsonb_build_object('d','29x31x35','u',50)]::jsonb[]),
    ('Battery Terminal',0.29,null,null,null,null,array[jsonb_build_object('d','33x25x44','u',50)]::jsonb[]),
    ('Baby Machine',0.3,null,null,null,null,array[jsonb_build_object('d','30x35x50','u',60)]::jsonb[]),
    ('Beer Cover',0.14,null,null,'Regular (7x4x2)',null,array[jsonb_build_object('d','36x50x37','u',200)]::jsonb[]),
    ('Bearing Puller',5,null,null,null,null,array[jsonb_build_object('d','24x36x37','u',5)]::jsonb[]),
    ('Bike Charger',0.12,null,null,null,null,array[jsonb_build_object('d','22x40x54','u',200)]::jsonb[]),
    ('Bike Mobile Holder',0.39,null,null,'8x5x2.5',null,array[jsonb_build_object('d','29x36x58','u',50)]::jsonb[]),
    ('B-Laser Meter',0.181,null,null,'Regular (7x4x2)',null,array[]::jsonb[]),
    ('Blue Meter Tape',0.42,null,null,'7x5x3.5',null,array[]::jsonb[]),
    ('BM560 Battery Tester',0.3,null,null,'8x4x4',null,array[jsonb_build_object('d','26x29x33','u',30)]::jsonb[]),
    ('Brest Pump',0.38,null,null,null,null,array[]::jsonb[]),
    ('Button 6A Car Battery',0.5,null,null,'10x4.5x4',null,array[]::jsonb[]),
    ('C30 Endoscope',0.53,null,null,null,null,array[jsonb_build_object('d','38x42x46','u',18)]::jsonb[]),
    ('Cable Protector',0.02,null,null,'Regular (7x4x2)',null,array[]::jsonb[]),
    ('Capacity Controller',0.06,null,null,'Regular (7x4x2)',null,array[]::jsonb[]),
    ('Car Handle',0.19,null,null,'Regular (7x4x2)',null,array[jsonb_build_object('d','31x60x38','u',50)]::jsonb[]),
    ('Car Vanity Mirror',0.41,null,null,'13x9x2',null,array[jsonb_build_object('d','25X30X40','u',30)]::jsonb[]),
    ('Card Dealer',1.04,null,null,'9.5x7x5.5',null,array[jsonb_build_object('d','26x41x44','u',12)]::jsonb[]),
    ('Card Shuffler',0.55,null,null,null,null,array[jsonb_build_object('d','13x20x44','u',18)]::jsonb[]),
    ('Cat-Yellow Microscope',0.27,null,null,null,null,array[jsonb_build_object('d','30x34x42','u',48)]::jsonb[]),
    ('CDSA',0.03,null,null,'Regular (7x4x2)','4x6 Bag',array[]::jsonb[]),
    ('CDSP',0.07,null,null,'Regular (7x4x2)',null,array[jsonb_build_object('d','25x40x60','u',500)]::jsonb[]),
    ('CEP',0.12,null,null,'Regular (7x4x2)',null,array[]::jsonb[]),
    ('Chess Timer 4 Button',0.19,null,null,'Regular (7x4x2)',null,array[jsonb_build_object('d','37x39x57','u',100)]::jsonb[]),
    ('Coating Guage Meter',0.28,null,null,'8x5x2.5',null,array[jsonb_build_object('d','36x43x61','u',100)]::jsonb[]),
    ('Cool Bag-Blue',0.64,null,null,'10x4.5x4',null,array[jsonb_build_object('d','28x45x50','u',25)]::jsonb[]),
    ('Dancing Lamp',1.179,null,null,null,null,array[jsonb_build_object('d','36x48x59','u',18)]::jsonb[]),
    ('DC Power Supply',1.52,null,null,'13x9x6',null,array[jsonb_build_object('d','40x44x57','u',12), jsonb_build_object('d','40x36x55','u',8)]::jsonb[]),
    ('DCEP',0.15,null,null,'Regular (7x4x2)',null,array[]::jsonb[]),
    ('Death Whistle',0.387,null,null,'7x6x3.5',null,array[jsonb_build_object('d','40x60x38','u',48)]::jsonb[]),
    ('Decible Meter',0.2,null,null,'Regular (7x4x2)',null,array[jsonb_build_object('d','39x43x43','u',100)]::jsonb[]),
    ('Di fluid Refractometer',0.21,null,null,null,null,array[jsonb_build_object('d','15x27x39','u',20)]::jsonb[]),
    ('Digital Hygrometer',0.19,null,null,'Regular (7x4x2)',null,array[jsonb_build_object('d','21x38x42','u',80), jsonb_build_object('d','20x24x41','u',40)]::jsonb[]),
    ('Digital Energy Meter',0.141,null,null,'Regular (7x4x2)',null,array[jsonb_build_object('d','25x38x37','u',100)]::jsonb[]),
    ('Diwali Lamp',0.07,null,null,null,null,array[jsonb_build_object('d','30x50x50','u',100)]::jsonb[]),
    ('DMX512 Light Controller',1.7,null,null,null,null,array[jsonb_build_object('d','36x50x55','u',10)]::jsonb[]),
    ('Door Chime',0.14,null,null,null,null,array[jsonb_build_object('d','42x42x43','u',100)]::jsonb[]),
    ('EMF Meter',0.25,null,null,'8x5x2.5',null,array[jsonb_build_object('d','38x43x46','u',100)]::jsonb[]),
    ('ESP32-S3 DevKit',0.02,null,null,null,null,array[jsonb_build_object('d','10x27x35','u',100)]::jsonb[]),
    ('Erasable Pen-2nd',0.1,null,null,'Regular (7x4x2)',null,array[]::jsonb[]),
    ('Eye Lash Curler',0.12,null,null,'8x5x2.5',null,array[]::jsonb[]),
    ('Face Paint',0.28,null,null,'13x9x2',null,array[]::jsonb[]),
    ('Face Tracking Tripod',0.33,null,null,'8x4x4',null,array[jsonb_build_object('d','25x30x50','u',50)]::jsonb[]),
    ('Float Valve',0.27,null,null,null,null,array[jsonb_build_object('d','31x33x50','u',100)]::jsonb[]),
    ('FNIRSI Moisture Meter',0.24,null,null,'8x5x2.5',null,array[jsonb_build_object('d','25x44x52','u',null)]::jsonb[]),
    ('FNIRSI Radiation Detector',0.23,null,null,'8x5x2.5',null,array[jsonb_build_object('d','32x42x47','u',50)]::jsonb[]),
    ('FNIRSI Stud Finder',0.27,null,null,'8x5x2.5',null,array[jsonb_build_object('d','25x43x51','u',50)]::jsonb[]),
    ('FNIRSI Blue Oscilloscope',0.29,null,null,'8x5x2.5',null,array[jsonb_build_object('d','27x44x56','u',50)]::jsonb[]),
    ('FNIRSI 1031D Oscilloscope',1.05,null,null,null,null,array[jsonb_build_object('d','29x33x52','u',10)]::jsonb[]),
    ('FNIRSI 2C3T Oscilloscope',0.73,null,null,null,null,array[jsonb_build_object('d','30x46x54','u',20)]::jsonb[]),
    ('FNIRSI DSO-510 Oscilloscope',0.29,null,null,null,null,array[jsonb_build_object('d','27x30x36','u',20)]::jsonb[]),
    ('FNIRSI DST-210 Oscilloscope',0.63,null,null,null,null,array[jsonb_build_object('d','23x48x56','u',25)]::jsonb[]),
    ('FNIRSI DMC-100 Clamp Meter',0.422,null,null,null,null,array[jsonb_build_object('d','29x47x59','u',50)]::jsonb[]),
    ('FNIRSI DMT-99 Multimeter',0.41,null,null,null,null,array[jsonb_build_object('d','42x45x60','u',50)]::jsonb[]),
    ('FNIRSI HRM-10 Resistance Tester',0.458,null,null,null,null,array[jsonb_build_object('d','39x45x60','u',50)]::jsonb[]),
    ('FNIRSI LCR-ST1 Tweezer',0.16,null,null,null,null,array[jsonb_build_object('d','23x44x45','u',50)]::jsonb[]),
    ('FNIRSI Soldering Iron',0.621,null,null,null,null,array[jsonb_build_object('d','27x42x46','u',20)]::jsonb[]),
    ('FNIRSI DPS-150 Power Supply',0.4,null,null,null,null,array[jsonb_build_object('d','21x42x54','u',20)]::jsonb[]),
    ('Foot Planter',0.13,null,null,'13.5x5x2.5','14.5x4.5x3 | 13x6 Bag',array[jsonb_build_object('d','40x50x60','u',100)]::jsonb[]),
    ('Ghost Detector',0.08,null,null,'Regular (7x4x2)',null,array[jsonb_build_object('d','32x40x45','u',150)]::jsonb[]),
    ('GOYOJO Refractometer',0.39,null,null,'8x5x2.5',null,array[jsonb_build_object('d','26x45x57','u',45)]::jsonb[]),
    ('GPU Stand',0.032,null,null,null,null,array[jsonb_build_object('d','25x25x35','u',200)]::jsonb[]),
    ('Green Laser Level',1.29,null,null,'9x9x8',null,array[jsonb_build_object('d','34x41x59','u',12)]::jsonb[]),
    ('Guitar Capo',0.08,null,null,null,null,array[jsonb_build_object('d','30x35x36','u',150), jsonb_build_object('d','25x25x30','u',50)]::jsonb[]),
    ('HABOTEST EMF Meter',0.26,null,null,'8x5x2.5',null,array[jsonb_build_object('d','27x34x41','u',50)]::jsonb[]),
    ('HABOTEST Gas Leak',0.36,null,null,'13.5x5x2.5',null,array[jsonb_build_object('d','30x49x49','u',40)]::jsonb[]),
    ('Hand Drum',0.948,null,null,null,null,array[jsonb_build_object('d','30x45x45','u',12)]::jsonb[]),
    ('Hand Warmer',0.18,null,null,null,null,array[jsonb_build_object('d','18x24x27','u',48)]::jsonb[]),
    ('Hanging Keychain Light',0.1,null,null,'Regular (7x4x2)',null,array[]::jsonb[]),
    ('Hanmatek Laser Meter',0.19,null,null,'Regular (7x4x2)',null,array[jsonb_build_object('d','29x52x65','u',100)]::jsonb[]),
    ('Hanmatek Volage Tester',0.06,null,null,'Regular (7x4x2)',null,array[jsonb_build_object('d','16x27x37','u',50)]::jsonb[]),
    ('Hanmatek Stud Finder',0.3,null,null,null,null,array[jsonb_build_object('d','27x40x43','u',40)]::jsonb[]),
    ('Heat Press',0.61,null,null,'7.5x7.5x5.75',null,array[jsonb_build_object('d','34x34x60','u',24)]::jsonb[]),
    ('HIMI-12',0.301,null,null,null,null,array[jsonb_build_object('d','21x30x39','u',32)]::jsonb[]),
    ('HIMI-18',0.921,null,null,null,null,array[jsonb_build_object('d','28x29x35','u',12)]::jsonb[]),
    ('HIMI-24',1.22,null,null,null,null,array[jsonb_build_object('d','25x29x41','u',10)]::jsonb[]),
    ('HIMI-36',0.89,null,null,null,null,array[jsonb_build_object('d','28x29x35','u',12)]::jsonb[]),
    ('HIMI-48',1.21,null,null,null,null,array[jsonb_build_object('d','25x29x41','u',10)]::jsonb[]),
    ('HIMI-56',2.72,null,null,null,null,array[jsonb_build_object('d','26x30x37','u',5)]::jsonb[]),
    ('HIMI-72',1.52,null,null,null,null,array[jsonb_build_object('d','22x31x35','u',6)]::jsonb[]),
    ('HIMI-112',2.53,null,null,null,null,array[jsonb_build_object('d','24x29x35','u',5)]::jsonb[]),
    ('Hole Punch',0.191,null,null,null,null,array[jsonb_build_object('d','32x37x38','u',100)]::jsonb[]),
    ('Hydraulic Crimper',2.68,null,null,'12x6x5',null,array[jsonb_build_object('d','17x36x40','u',5)]::jsonb[]),
    ('Kalimba 21',0.499,null,null,null,null,array[jsonb_build_object('d','38x43x53','u',30)]::jsonb[]),
    ('Lanyard Diamond Moti',0.08,null,null,'Regular (7x4x2)',null,array[]::jsonb[]),
    ('Lanyard Diamond Round',0.05,null,null,'Regular (7x4x2)',null,array[]::jsonb[]),
    ('Lanyard-Black',0.12,null,null,'Regular (7x4x2)',null,array[]::jsonb[]),
    ('Light Meter',0.141,null,null,'Regular (7x4x2)',null,array[jsonb_build_object('d','20x40x52','u',100), jsonb_build_object('d','22x27x42','u',50)]::jsonb[]),
    ('Magic Cloth Wrap',0.11,null,null,'Regular (7x4x2)',null,array[]::jsonb[]),
    ('MAYILON Clamp Multimeter',0.42,null,null,null,null,array[]::jsonb[]),
    ('MESTEK Clamp Meter',0.43,null,null,'Regular (7x4x2)',null,array[jsonb_build_object('d','30x44x56','u',50)]::jsonb[]),
    ('Metal-Laptop Stand',0.1,null,null,'Regular (7x4x2)',null,array[jsonb_build_object('d','12x20x22','u',100)]::jsonb[]),
    ('MPPT SCC',0.17,null,null,null,null,array[jsonb_build_object('d','27x36x43','u',100)]::jsonb[]),
    ('Decibel Meter',0.2,null,null,'Regular (7x4x2)',null,array[]::jsonb[]),
    ('Microscope',0.331,null,null,'8x5x2.5',null,array[]::jsonb[]),
    ('Mini Coating Guage Meter',0.082,null,null,'Regular (7x4x2)',null,array[jsonb_build_object('d','17x22x43','u',100)]::jsonb[]),
    ('Mini EDC Light',0.03,null,null,'Regular (7x4x2)',null,array[jsonb_build_object('d','42x27x62','u',300)]::jsonb[]),
    ('MF Watch',0.21,null,null,null,null,array[jsonb_build_object('d','29x31x41','u',50)]::jsonb[]),
    ('Monocular',1.32,null,null,'13x9x6',null,array[jsonb_build_object('d','40x32x19','u',10)]::jsonb[]),
    ('MT28C-Moisture Meter',0.24,null,null,null,null,array[jsonb_build_object('d','36x44x47','u',100)]::jsonb[]),
    ('Nasal Aspirator - 4',0.33,null,null,'8x5x2.5',null,array[jsonb_build_object('d','38x59x27','u',40)]::jsonb[]),
    ('Nasal Aspirator Green',0.24,null,null,'8x5x2.5',null,array[jsonb_build_object('d','30x37x50','u',50)]::jsonb[]),
    ('NES430 Endoscope',0.5,null,null,null,null,array[jsonb_build_object('d','32x38x50','u',36)]::jsonb[]),
    ('New 10A Car Battery',0.7,null,null,'10x7x3',null,array[jsonb_build_object('d','36x40x43','u',30)]::jsonb[]),
    ('New Meter Tape',0.372,null,null,null,null,array[jsonb_build_object('d','29x36x40','u',36), jsonb_build_object('d','29x36x35','u',28)]::jsonb[]),
    ('Optical Meter',0.231,null,null,'Regular (7x4x2)',null,array[jsonb_build_object('d','34x56x43','u',100), jsonb_build_object('d','29x31x41','u',50)]::jsonb[]),
    ('Orange 6A Car Battery',0.52,null,null,'10x4.5x4',null,array[jsonb_build_object('d','33x35x41','u',30)]::jsonb[]),
    ('Otoscope',0.299,null,null,'8x5x2.5',null,array[jsonb_build_object('d','20x25x25','u',20)]::jsonb[]),
    ('Q10 Digital Otoscope',0.13,null,null,null,null,array[jsonb_build_object('d','26x40x55','u',40)]::jsonb[]),
    ('Quick Connector',0.26,null,null,null,null,array[jsonb_build_object('d','x','u',100)]::jsonb[]),
    ('Ozone Generator',2.05,null,null,'9x9x8',null,array[jsonb_build_object('d','36x45x43','u',8)]::jsonb[]),
    ('P Table Real',0.94,null,null,'10x7x3',null,array[jsonb_build_object('d','16x22x46','u',10)]::jsonb[]),
    ('Paper Roll Cutter',0.29,null,null,null,null,array[]::jsonb[]),
    ('Plastic Welding Gun',0.95,null,null,'13x9x2',null,array[jsonb_build_object('d','25x50x55','u',20)]::jsonb[]),
    ('Pomodoro Timer',0.068,null,null,'6x4x4','6x8 Bag',array[jsonb_build_object('d','20x25x31','u',60), jsonb_build_object('d','9x29x35','u',20)]::jsonb[]),
    ('Projector Ubhu',1.39,null,null,'9x9x8',null,array[]::jsonb[]),
    ('Pulse Massager',0.1,null,null,'8x5x2.5',null,array[]::jsonb[]),
    ('Knuckle Sticker',0.1,null,null,'Regular (7x4x2)',null,array[jsonb_build_object('d','25x27x29','u',200)]::jsonb[]),
    ('New Raclette Grill',3.06,null,null,'17.5x12x7',null,array[jsonb_build_object('d','30x40x45','u',3)]::jsonb[]),
    ('Resin Light',0.432,null,null,'8x4x4',null,array[jsonb_build_object('d','28x50x52','u',50)]::jsonb[]),
    ('RGBW DJ Light',3.6,null,null,'8x4x5',null,array[jsonb_build_object('d','37x50x50','u',4)]::jsonb[]),
    ('Round-Yellow Microscope',0.24,null,null,null,null,array[jsonb_build_object('d','28x36x40','u',60)]::jsonb[]),
    ('S8607 Sound Meter',0.13,null,null,null,null,array[jsonb_build_object('d','23x42x50','u',100)]::jsonb[]),
    ('S288 Amplifier',0.88,null,null,'12x9.5x4',null,array[jsonb_build_object('d','26x38x50','u',16), jsonb_build_object('d','13x38x50','u',8)]::jsonb[]),
    ('Satellite Finder',0.608,null,null,'9x9x3',null,array[jsonb_build_object('d','26x33x43','u',10)]::jsonb[]),
    ('Selfie Monitor Screen',0.15,null,null,null,null,array[jsonb_build_object('d','27x28x35','u',50)]::jsonb[]),
    ('Sheep Hair Cutter',3.16,null,null,'18x9x5',null,array[jsonb_build_object('d','19x40x51','u',5)]::jsonb[]),
    ('Sizzix Die Cutting',5.38,null,null,null,null,array[jsonb_build_object('d',null,'u',3)]::jsonb[]),
    ('SMD Station',1.71,null,null,null,null,array[jsonb_build_object('d','37x41x54','u',12)]::jsonb[]),
    ('SMEG Kettle',2.7,null,null,null,null,array[jsonb_build_object('d','34x50x50','u',4)]::jsonb[]),
    ('Smoke Machine',1.928,null,null,'13x9x6',null,array[jsonb_build_object('d','34x55x38','u',8)]::jsonb[]),
    ('Soil Tester',0.14,null,null,null,null,array[jsonb_build_object('d','29x46x49','u',104)]::jsonb[]),
    ('Soldering Iron Station',0.93,null,null,null,null,array[jsonb_build_object('d','35x40x50','u',18)]::jsonb[]),
    ('Solar Charge Controller',0.13,null,null,null,null,array[jsonb_build_object('d','20x39x56','u',100)]::jsonb[]),
    ('Square Baby Machine',0.29,null,null,null,null,array[jsonb_build_object('d','30x35x50','u',60)]::jsonb[]),
    ('SS Laser Pointer',0.08,null,null,'Regular (7x4x2)',null,array[jsonb_build_object('d','32x36x45','u',200)]::jsonb[]),
    ('Staple Gun',1.14,null,null,'9x9x3',null,array[jsonb_build_object('d','21x32x43','u',10)]::jsonb[]),
    ('Stroller Fan',0.4,null,null,'9.5x7x5.5',null,array[]::jsonb[]),
    ('TASI Tacho Meter',0.209,null,null,'8x5x2.5',null,array[jsonb_build_object('d','23x32x37','u',40), jsonb_build_object('d','34x25x38','u',30), jsonb_build_object('d','13x36x46','u',20)]::jsonb[]),
    ('Temtop AQM-S1',0.159,null,null,'8x5x2.5',null,array[jsonb_build_object('d','38x38x45','u',99)]::jsonb[]),
    ('Thermal Pad 4*8',0.032,null,null,'Regular (7x4x2)',null,array[jsonb_build_object('d','31x31x40','u',100)]::jsonb[]),
    ('Thermal Grizzly',0.02,null,null,null,null,array[jsonb_build_object('d','28x44x45','u',500)]::jsonb[]),
    ('Thermalright PA120SE',1.5,null,null,'9x9x8',null,array[jsonb_build_object('d','32x36x52','u',8)]::jsonb[]),
    ('Thermalright PA120SE ARGB',1.5,null,null,'9x9x8',null,array[jsonb_build_object('d','32x36x52','u',8)]::jsonb[]),
    ('Thermalright PS120SE',1.5,null,null,'9x9x8',null,array[jsonb_build_object('d','32x36x52','u',8)]::jsonb[]),
    ('Thermalright PS120SE ARGB',1.5,null,null,'9x9x8',null,array[jsonb_build_object('d','32x36x52','u',8)]::jsonb[]),
    ('Thermalright AX 120R SE',0.83,null,null,null,null,array[jsonb_build_object('d','22x50x50','u',12)]::jsonb[]),
    ('Tissue Bag Grey',0.1,null,null,'Regular (7x4x2)',null,array[]::jsonb[]),
    ('Tissue Bag-Green',0.1,null,null,'Regular (7x4x2)',null,array[]::jsonb[]),
    ('Torque Multiplier',11,null,null,null,null,array[jsonb_build_object('d','11x33x40','u',1)]::jsonb[]),
    ('Torch',0.64,null,null,'12x4x3',null,array[]::jsonb[]),
    ('TP31 Tattoo Printer',0.522,null,null,null,null,array[jsonb_build_object('d','32x41x57','u',32), jsonb_build_object('d','32x37x52','u',30), jsonb_build_object('d','32x35x48','u',28), jsonb_build_object('d','25x34x46','u',21), jsonb_build_object('d','25x30x45','u',19)]::jsonb[]),
    ('TP358 ThermoPro',0.14,null,null,'Regular (7x4x2)',null,array[jsonb_build_object('d','24x30x43','u',102)]::jsonb[]),
    ('TP49 ThermoPro',0.11,null,null,'Regular (7x4x2)',null,array[jsonb_build_object('d','27x32x40','u',150)]::jsonb[]),
    ('Transistor Tester',0.14,null,null,'Regular (7x4x2)',null,array[jsonb_build_object('d','25x25x30','u',50), jsonb_build_object('d','21x41x43','u',100)]::jsonb[]),
    ('Transparent Lighter',0.05,null,null,'Regular (7x4x2)',null,array[jsonb_build_object('d','38x25x37','u',300), jsonb_build_object('d','38x24x26','u',200)]::jsonb[]),
    ('Turbo Nozzle',0.37,null,null,'Regular (7x4x2)',null,array[jsonb_build_object('d','17x45x57','u',50)]::jsonb[]),
    ('Tyre Depth Meter',0.032,null,null,'Regular (7x4x2)',null,array[jsonb_build_object('d','18x20x30','u',100)]::jsonb[]),
    ('USB Tester',0.03,null,null,'Regular (7x4x2)',null,array[jsonb_build_object('d','17x33x38','u',100)]::jsonb[]),
    ('UV Light',0.07,null,null,'Regular (7x4x2)',null,array[jsonb_build_object('d','30x39x57','u',280), jsonb_build_object('d','32x41x49','u',240)]::jsonb[]),
    ('Vacuum Sealer',1.01,null,null,null,null,array[jsonb_build_object('d','21x37x45','u',15)]::jsonb[]),
    ('Voice Recorder',0.082,null,null,null,null,array[jsonb_build_object('d','25x36x40','u',100)]::jsonb[]),
    ('W608 PCB Holder',1.592,null,null,'13x9x2',null,array[jsonb_build_object('d','25x31x47','u',10)]::jsonb[]),
    ('Water Flow Meter',0.135,null,null,'Regular (7x4x2)',null,array[jsonb_build_object('d','29x34x51','u',100)]::jsonb[]),
    ('Watch Winder',1.14,null,null,null,null,array[jsonb_build_object('d','34x43x45','u',12)]::jsonb[]),
    ('Weather Station Big',1.9,null,null,'17.5x12x7',null,array[jsonb_build_object('d','33x41x55','u',3)]::jsonb[]),
    ('White Soap Dispenser',0.33,null,null,'9x9x3',null,array[jsonb_build_object('d','43x44x54','u',50)]::jsonb[]),
    ('Yellow Temp Indicator',0.15,null,null,null,null,array[jsonb_build_object('d','39x41x59','u',100)]::jsonb[]),
    ('Yellow Manometer',0.31,null,null,'8x5x2.5',null,array[jsonb_build_object('d','27x36x44','u',50), jsonb_build_object('d','23x26x48','u',30)]::jsonb[]),
    ('Ubhu Microscope',0.24,null,null,'7x5x3.5',null,array[jsonb_build_object('d','42x45x52','u',40), jsonb_build_object('d','30x42x52','u',60)]::jsonb[]),
    ('Wire Stripping Machine',1.7,null,null,null,null,array[jsonb_build_object('d','26x38x40','u',10)]::jsonb[]),
    ('Work Light',0.16,null,null,null,null,array[jsonb_build_object('d','31x39x40','u',100)]::jsonb[])
  ), ins as (
    insert into public.pbs_products (name, unit_weight, fba_unit, item_dimension, item_box_dimension, notes)
    select name, unit_weight, fba_unit, item_dimension, item_box_dimension, notes from src
    returning id, name
  )
  insert into public.pbs_boxes (product_id, box_dimension, unit_in_box, sort_order)
  select ins.id, nullif(b.elem->>'d',''), (b.elem->>'u')::numeric::int, b.ord - 1
  from src join ins on ins.name = src.name,
  lateral unnest(src.boxes) with ordinality as b(elem, ord);

  insert into public.pbs_bags (code, product, sort_order) values
    ('SB0','4.5x4.5x1.5',0),
    ('SB1','7x4x2 & 8x4x4',1),
    ('SB2','Meter Tape',2),
    ('SB3.5','Heat Press & Foot Plantar',3),
    ('SB4','Room Heater & Split End Trim',4),
    ('SB5','Sheep Haie Cutter',5);
end $$;
