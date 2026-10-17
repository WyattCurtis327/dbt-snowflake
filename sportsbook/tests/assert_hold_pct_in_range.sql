{{ config(severity='warn') }}
-- Hold % outside [-100%, 100%] usually means a units/join bug (fan-out, cents vs dollars)...
-- ...but on tiny samples a few big winners can legitimately push hold below -100%. So: WARN, don't fail.
select * from {{ ref('mart_state_hold_ngr') }}
where hold_pct < -1 or hold_pct > 1
