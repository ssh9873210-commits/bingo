-- 빙고 게임용 테이블과 접근 규칙
-- Supabase 대시보드 → SQL Editor에 통째로 붙여 넣고 Run 하세요.
-- 맨 아래 이메일을 진행자(선생님) 계정 이메일로 바꾼 뒤 실행하세요.

-- 1) 게임 상태: 한 줄(id = 1)에 용어, 없앤 용어, 칸 교환 기록을 저장합니다.
create table if not exists public.game_state (
  id integer primary key,
  data jsonb not null,
  updated_at timestamptz not null default now()
);

-- 2) 진행자 목록: 여기에 등록된 이메일만 게임을 바꿀 수 있습니다.
create table if not exists public.game_hosts (
  email text primary key
);

alter table public.game_state enable row level security;
alter table public.game_hosts enable row level security;  -- 정책이 없으므로 외부에서 읽기/쓰기 불가

-- 로그인한 사람이 진행자인지 확인하는 함수
create or replace function public.is_bingo_host()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.game_hosts
    where lower(email) = lower(coalesce(auth.jwt() ->> 'email', ''))
  );
$$;

-- 학생(로그인 없음)과 진행자 모두 읽기 가능
drop policy if exists "bingo read" on public.game_state;
create policy "bingo read" on public.game_state
  for select to anon, authenticated using (true);

-- 진행자만 쓰기 가능
drop policy if exists "bingo host insert" on public.game_state;
create policy "bingo host insert" on public.game_state
  for insert to authenticated with check (public.is_bingo_host());

drop policy if exists "bingo host update" on public.game_state;
create policy "bingo host update" on public.game_state
  for update to authenticated using (public.is_bingo_host()) with check (public.is_bingo_host());

-- 3) 실시간 반영 켜기
do $$
begin
  alter publication supabase_realtime add table public.game_state;
exception when duplicate_object then null;
end $$;

-- 4) 첫 게임 (전기 단원 용어 30개, FREE 칸 없음)
insert into public.game_state (id, data) values (1, '{
  "title": "빙고", "free": false, "round": 1, "removed": [], "swaps": [],
  "terms": ["마찰 전기","정전기","정전기 유도","전기력","대전","대전체","검전기","전류","A(암페어)","전압","V(볼트)","저항","Ω(옴)","옴의 법칙","도체","반도체","부도체","소비 전력","W(와트)","전기 에너지","자기력","자기장","코일","전자석","전동기","저항의 직렬연결","저항의 병렬연결","전자의 이동 방향","전류의 방향","나침반"]
}'::jsonb)
on conflict (id) do nothing;

-- 5) 진행자 이메일 등록 (아래 이메일을 바꾸세요)
insert into public.game_hosts (email) values ('teacher@example.com')
on conflict (email) do nothing;
