-- 004_catalogue.sql
-- Product catalogue with MAT codes (spec §3). Replaces V1 rates.hardware {type, cost}.

CREATE TABLE suppliers (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name         text NOT NULL UNIQUE,
  account_code text,
  contact      text,
  phone        text,
  email        text,
  active       boolean NOT NULL DEFAULT true,
  version      integer NOT NULL DEFAULT 1,
  created_at   timestamptz NOT NULL DEFAULT now(),
  created_by   text REFERENCES app_users (uid),
  updated_at   timestamptz NOT NULL DEFAULT now(),
  updated_by   text REFERENCES app_users (uid)
);
CREATE TRIGGER suppliers_touch BEFORE UPDATE ON suppliers FOR EACH ROW EXECUTE FUNCTION touch_row();

-- Categories are data, not code (spec CAT-02). `door_field_key` is the column key the door
-- grid and the Excel import use (V1 field names: hinge, closer, ...), so the grid, exports
-- and import mapping are all driven from this table instead of ~10 copied lists.
CREATE TABLE product_categories (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  key                text NOT NULL UNIQUE CHECK (key ~ '^[a-zA-Z][a-zA-Z0-9]*$'),
  label              text NOT NULL,
  door_field_key     text UNIQUE CHECK (door_field_key ~ '^[a-zA-Z][a-zA-Z0-9]*$'),
  show_on_door_grid  boolean NOT NULL DEFAULT true,
  default_product_id uuid,          -- FK added below (circular with products)
  default_qty        numeric(10,2) NOT NULL DEFAULT 1 CHECK (default_qty > 0),
  sort               integer NOT NULL DEFAULT 0,
  active             boolean NOT NULL DEFAULT true,
  version            integer NOT NULL DEFAULT 1,
  created_at         timestamptz NOT NULL DEFAULT now(),
  created_by         text REFERENCES app_users (uid),
  updated_at         timestamptz NOT NULL DEFAULT now(),
  updated_by         text REFERENCES app_users (uid)
);
CREATE TRIGGER product_categories_touch BEFORE UPDATE ON product_categories FOR EACH ROW EXECUTE FUNCTION touch_row();

-- Products (spec CAT-01). Quantity is NOT part of the product (CAT-03).
-- MAT code is unique; it may be blank while a product is unverified, but a verified
-- product must have one.
CREATE TABLE products (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  mat_code      text UNIQUE CHECK (mat_code IS NULL OR mat_code = upper(btrim(mat_code))),
  description   text NOT NULL,
  category_id   uuid NOT NULL REFERENCES product_categories (id),
  supplier_id   uuid REFERENCES suppliers (id),
  supplier_code text,
  finish        text,
  unit          text NOT NULL DEFAULT 'each' CHECK (unit IN ('each', 'pair', 'set', 'metre', 'm2')),
  cost          numeric(12,2) NOT NULL DEFAULT 0 CHECK (cost >= 0),
  list_price    numeric(12,2) CHECK (list_price >= 0),
  active        boolean NOT NULL DEFAULT true,
  verified      boolean NOT NULL DEFAULT false,   -- CAT-09: on-the-fly adds await admin approval
  notes         text,
  image_url     text,
  -- Search text: everything a user might type, lower-cased. Trigram-indexed below.
  search_text   text GENERATED ALWAYS AS (
                  lower(coalesce(mat_code, '') || ' ' || coalesce(supplier_code, '') || ' ' ||
                        description || ' ' || coalesce(finish, ''))
                ) STORED,
  version       integer NOT NULL DEFAULT 1,
  created_at    timestamptz NOT NULL DEFAULT now(),
  created_by    text REFERENCES app_users (uid),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  updated_by    text REFERENCES app_users (uid),
  CHECK (NOT verified OR mat_code IS NOT NULL),
  UNIQUE (id, category_id)          -- target for the category default FK below
);
CREATE TRIGGER products_touch BEFORE UPDATE ON products FOR EACH ROW EXECUTE FUNCTION touch_row();
CREATE INDEX products_category_idx ON products (category_id) WHERE active;
CREATE INDEX products_supplier_code_idx ON products (supplier_id, lower(supplier_code));
CREATE INDEX products_search_trgm ON products USING gin (search_text gin_trgm_ops);

-- A category's default product must belong to that category.
ALTER TABLE product_categories
  ADD CONSTRAINT product_categories_default_fk
  FOREIGN KEY (default_product_id, id) REFERENCES products (id, category_id)
  DEFERRABLE INITIALLY DEFERRED;

-- Price history (spec CAT-07): every cost change, who and when.
CREATE TABLE product_cost_history (
  id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  product_id uuid NOT NULL REFERENCES products (id) ON DELETE CASCADE,
  old_cost   numeric(12,2) NOT NULL,
  new_cost   numeric(12,2) NOT NULL,
  changed_at timestamptz NOT NULL DEFAULT now(),
  changed_by text REFERENCES app_users (uid)
);
CREATE INDEX product_cost_history_product_idx ON product_cost_history (product_id, changed_at DESC);

CREATE FUNCTION record_product_cost() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO product_cost_history (product_id, old_cost, new_cost, changed_by)
  VALUES (NEW.id, OLD.cost, NEW.cost, NEW.updated_by);
  RETURN NEW;
END $$;
CREATE TRIGGER products_cost_history AFTER UPDATE OF cost ON products
  FOR EACH ROW WHEN (OLD.cost IS DISTINCT FROM NEW.cost) EXECUTE FUNCTION record_product_cost();
