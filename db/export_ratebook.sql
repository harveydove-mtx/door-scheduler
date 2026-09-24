-- Export the current rates as one JSON "rate book", in the shape the pricing engine
-- (app/src/domain/pricing.ts) takes. Used to generate app/src/domain/fixtures/seedRateBook.json
-- from a freshly seeded database, so the engine tests use exactly the seeded prices:
--   psql "$DATABASE_URL" -X -A -t -f db/export_ratebook.sql > app/src/domain/fixtures/seedRateBook.json
-- Door types are keyed by form code and architraves by code (the real app uses row ids).
SELECT jsonb_pretty(jsonb_build_object(
  'liningDepthThresholdMm', lining_depth_threshold_mm(),
  'fireRatings', (SELECT jsonb_agg(jsonb_build_object('code', code, 'baseCode', base_code, 'isFireDoor', is_fire_door) ORDER BY sort) FROM fire_ratings),
  'doorFinishes', (SELECT jsonb_agg(jsonb_build_object('code', code, 'baseFinishCode', base_finish_code) ORDER BY sort) FROM door_finishes),
  'doorTypes', (SELECT jsonb_agg(jsonb_build_object('id', form_code, 'formCode', form_code, 'description', description,
                                                   'needsFlushBolts', needs_flush_bolts) ORDER BY sort) FROM door_types),
  'doorRates', (SELECT jsonb_agg(jsonb_build_object('doorTypeId', dt.form_code, 'fireRatingCode', r.fire_rating_code,
                                                   'finishCode', r.finish_code, 'price', r.price, 'matCode', r.mat_code)
                                 ORDER BY dt.sort, r.fire_rating_code, r.finish_code)
                FROM door_rates r JOIN door_types dt ON dt.id = r.door_type_id),
  'vpRates', (SELECT jsonb_agg(jsonb_build_object('fireRatingCode', fire_rating_code, 'price', price, 'matCode', mat_code)
                               ORDER BY fire_rating_code) FROM vp_rates),
  'frameRates', (SELECT jsonb_agg(jsonb_build_object('doorTypeId', dt.form_code, 'finishCode', r.finish_code,
                                                    'price', r.price, 'matCode', r.mat_code) ORDER BY dt.sort, r.finish_code)
                 FROM frame_rates r JOIN door_types dt ON dt.id = r.door_type_id),
  'liningRates', coalesce((SELECT jsonb_agg(jsonb_build_object('doorTypeId', dt.form_code, 'finishCode', r.finish_code,
                                                    'price', r.price, 'matCode', r.mat_code) ORDER BY dt.sort, r.finish_code)
                 FROM lining_rates r JOIN door_types dt ON dt.id = r.door_type_id), '[]'),
  'architraves', (SELECT jsonb_agg(jsonb_build_object('id', code, 'price', price, 'matCode', mat_code) ORDER BY sort) FROM architrave_types),
  'overPanelRates', (SELECT jsonb_agg(jsonb_build_object('doorTypeId', dt.form_code, 'fireRatingCode', r.fire_rating_code,
                                                        'panelTypeCode', r.panel_type_code, 'finishCode', r.finish_code,
                                                        'price', r.price, 'matCode', r.mat_code)
                                     ORDER BY dt.sort, r.fire_rating_code, r.panel_type_code)
                     FROM over_panel_rates r JOIN door_types dt ON dt.id = r.door_type_id)
));
