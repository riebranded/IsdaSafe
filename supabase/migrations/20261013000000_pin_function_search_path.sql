-- Security advisor (function_search_path_mutable): pin the search_path of
-- the alert maths helpers, so a look-alike function in another schema can
-- never be picked up instead of the built-ins they call. What they compute
-- is unchanged.
alter function public.free_ammonia(real, real, real) set search_path = '';
alter function public.water_reading_status(text, real) set search_path = '';
