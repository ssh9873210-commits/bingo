-- 단어 맞추기 랭킹용 테이블과 규칙
-- supabase.sql(빙고)을 먼저 실행한 뒤, 이 파일을 SQL Editor에 통째로 붙여 넣고 Run 하세요.
-- 여러 번 실행해도 안전합니다. (기존 랭킹은 지워지지 않아요)

-- 1) 랭킹 테이블: 닉네임마다 한 줄, 가장 높은 점수만 남습니다.
create table if not exists public.word_scores (
  nick_key   text primary key,          -- 대소문자 구분 없이 같은 닉네임을 찾기 위한 값
  nickname   text not null,
  score      integer not null,
  created_at timestamptz not null default now()
);
alter table public.word_scores enable row level security;

-- 누구나(로그인 없는 학생 포함) 랭킹을 볼 수 있음
drop policy if exists "word read" on public.word_scores;
create policy "word read" on public.word_scores
  for select to anon, authenticated using (true);

-- 삭제는 진행자(game_hosts에 등록된 이메일)만
drop policy if exists "word host delete" on public.word_scores;
create policy "word host delete" on public.word_scores
  for delete to authenticated using (public.is_bingo_host());

grant select on public.word_scores to anon, authenticated;
grant delete on public.word_scores to authenticated;

-- 2) 점수 등록 함수: 학생은 이 함수로만 점수를 올릴 수 있어요.
--    같은 닉네임이 있으면 더 높은 점수만 남깁니다.
create or replace function public.submit_word_score(p_nickname text, p_score integer)
returns table (best_score integer, rank integer)
language plpgsql
security definer
set search_path = public
as $$
declare
  n text := btrim(coalesce(p_nickname, ''));
  k text;
begin
  if char_length(n) < 1 or char_length(n) > 10 then
    raise exception '닉네임은 1~10글자로 입력하세요';
  end if;
  if p_score is null or p_score < -1000 or p_score > 1000 then
    raise exception '점수가 올바르지 않아요';
  end if;
  k := lower(n);

  insert into public.word_scores as w (nick_key, nickname, score)
  values (k, n, p_score)
  on conflict (nick_key) do update
    set nickname = excluded.nickname, score = excluded.score, created_at = now()
    where excluded.score > w.score;

  return query
    select w.score,
           (select count(*)::integer + 1 from public.word_scores o where o.score > w.score)
    from public.word_scores w
    where w.nick_key = k;
end;
$$;

revoke all on function public.submit_word_score(text, integer) from public;
grant execute on function public.submit_word_score(text, integer) to anon, authenticated;
