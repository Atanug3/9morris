revoke all on function public.submit_game_state(uuid, integer, jsonb, text)
from authenticated;

drop function public.submit_game_state(uuid, integer, jsonb, text);