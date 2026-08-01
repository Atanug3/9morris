


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";






CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";





SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."games" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "room_code" "text" NOT NULL,
    "player1" "uuid" NOT NULL,
    "player2" "uuid",
    "player1_name" "text" NOT NULL,
    "player2_name" "text",
    "status" "text" DEFAULT 'waiting'::"text" NOT NULL,
    "game_state" "jsonb" NOT NULL,
    "revision" integer DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "games_status_check" CHECK (("status" = ANY (ARRAY['waiting'::"text", 'active'::"text", 'finished'::"text", 'abandoned'::"text"])))
);


ALTER TABLE "public"."games" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_game"("p_initial_state" "jsonb", "p_display_name" "text") RETURNS SETOF "public"."games"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  v_room_code text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if jsonb_typeof(p_initial_state -> 'board') <> 'array'
     or jsonb_array_length(p_initial_state -> 'board') <> 24 then
    raise exception 'Invalid initial game state';
  end if;

  loop
    v_room_code := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6));
    begin
      return query
      insert into public.games (
        room_code,
        player1,
        player1_name,
        game_state
      )
      values (
        v_room_code,
        auth.uid(),
        left(coalesce(nullif(trim(p_display_name), ''), 'Player 1'), 40),
        p_initial_state
      )
      returning *;
      return;
    exception
      when unique_violation then
        null;
    end;
  end loop;
end;
$$;


ALTER FUNCTION "public"."create_game"("p_initial_state" "jsonb", "p_display_name" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."join_game"("p_room_code" "text", "p_display_name" "text") RETURNS SETOF "public"."games"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if exists (
    select 1
    from public.games
    where room_code = upper(trim(p_room_code))
      and player1 = auth.uid()
  ) then
    raise exception 'You cannot join your own room as Player 2';
  end if;

  return query
  update public.games
  set player2 = auth.uid(),
      player2_name = left(coalesce(nullif(trim(p_display_name), ''), 'Player 2'), 40),
      status = 'active',
      updated_at = now()
  where room_code = upper(trim(p_room_code))
    and status = 'waiting'
    and player2 is null
  returning *;

  if not found then
    raise exception 'Room not found or already full';
  end if;
end;
$$;


ALTER FUNCTION "public"."join_game"("p_room_code" "text", "p_display_name" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."leave_game"("p_game_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
begin
  update public.games
  set status = 'abandoned',
      updated_at = now()
  where id = p_game_id
    and status in ('waiting', 'active')
    and (player1 = auth.uid() or player2 = auth.uid());
end;
$$;


ALTER FUNCTION "public"."leave_game"("p_game_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."rls_auto_enable"() RETURNS "event_trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table','partitioned table')
  LOOP
     IF cmd.schema_name IS NOT NULL AND cmd.schema_name IN ('public') AND cmd.schema_name NOT IN ('pg_catalog','information_schema') AND cmd.schema_name NOT LIKE 'pg_toast%' AND cmd.schema_name NOT LIKE 'pg_temp%' THEN
      BEGIN
        EXECUTE format('alter table if exists %s enable row level security', cmd.object_identity);
        RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      END;
     ELSE
        RAISE LOG 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
     END IF;
  END LOOP;
END;
$$;


ALTER FUNCTION "public"."rls_auto_enable"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."submit_game_state"("p_game_id" "uuid", "p_expected_revision" integer, "p_game_state" "jsonb", "p_status" "text") RETURNS SETOF "public"."games"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  v_game public.games%rowtype;
  v_expected_user uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select *
  into v_game
  from public.games
  where id = p_game_id
  for update;

  if not found then
    raise exception 'Game not found';
  end if;

  if v_game.status <> 'active' then
    raise exception 'Game is not active';
  end if;

  if v_game.revision <> p_expected_revision then
    raise exception 'Game state has changed; refresh and try again';
  end if;

  v_expected_user := case
    when v_game.game_state ->> 'currentPlayer' = 'P1' then v_game.player1
    else v_game.player2
  end;

  if auth.uid() <> v_expected_user then
    raise exception 'It is not your turn';
  end if;

  if jsonb_typeof(p_game_state -> 'board') <> 'array'
     or jsonb_array_length(p_game_state -> 'board') <> 24
     or p_game_state ->> 'currentPlayer' not in ('P1', 'P2')
     or p_game_state ->> 'phase' not in ('placement', 'movement') then
    raise exception 'Invalid game state';
  end if;

  return query
  update public.games
  set game_state = p_game_state,
      status = case when p_status = 'finished' then 'finished' else 'active' end,
      revision = revision + 1,
      updated_at = now()
  where id = p_game_id
  returning *;
end;
$$;


ALTER FUNCTION "public"."submit_game_state"("p_game_id" "uuid", "p_expected_revision" integer, "p_game_state" "jsonb", "p_status" "text") OWNER TO "postgres";


ALTER TABLE ONLY "public"."games"
    ADD CONSTRAINT "games_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."games"
    ADD CONSTRAINT "games_room_code_key" UNIQUE ("room_code");



ALTER TABLE ONLY "public"."games"
    ADD CONSTRAINT "games_player1_fkey" FOREIGN KEY ("player1") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."games"
    ADD CONSTRAINT "games_player2_fkey" FOREIGN KEY ("player2") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



CREATE POLICY "Participants can view their games" ON "public"."games" FOR SELECT TO "authenticated" USING ((("auth"."uid"() = "player1") OR ("auth"."uid"() = "player2")));



ALTER TABLE "public"."games" ENABLE ROW LEVEL SECURITY;




ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";






ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."games";



GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";






















































































































































GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."games" TO "service_role";
GRANT SELECT ON TABLE "public"."games" TO "authenticated";



REVOKE ALL ON FUNCTION "public"."create_game"("p_initial_state" "jsonb", "p_display_name" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_game"("p_initial_state" "jsonb", "p_display_name" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."join_game"("p_room_code" "text", "p_display_name" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."join_game"("p_room_code" "text", "p_display_name" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."leave_game"("p_game_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."leave_game"("p_game_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."submit_game_state"("p_game_id" "uuid", "p_expected_revision" integer, "p_game_state" "jsonb", "p_status" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."submit_game_state"("p_game_id" "uuid", "p_expected_revision" integer, "p_game_state" "jsonb", "p_status" "text") TO "authenticated";
























ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLES TO "service_role";



































