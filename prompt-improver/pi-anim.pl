#!/usr/bin/env perl
# pi-anim.pl — 대기 줄 연필 애니메이션(pi-edit 이 백그라운드로 띄우고 끝나면 TERM 으로 끈다).
# 화면: 한 줄 "<연필 트랙> <문구> <경과초>" 를 /dev/tty 에 80ms 마다 제자리 갱신. 줄은 터미널 폭-1 로 잘라 접히지 않게(OMC HUD 한 줄 원칙).
# 연필(앱 아이콘 '반짝이는 연필'): ✎ 가 오른쪽으로 쓱 가며 초안 ∿ 를 쓰고 → 되돌아오며 다듬은 줄 ‿⁀ 로 싹 바꾸고 → 끝에서 ✦ 반짝.
#   (거친 요청 → 다듬은 프롬프트). 글리프는 모두 동아시아 폭 N(한 칸) — 한글 환경 '모호 폭=두 칸' 터미널에서도 줄이 밀리지 않게.
#   프레임(색 포함)은 시작할 때 한 번 만들어 두고 매 틱엔 문자열만 쓴다.
# 입력: 인자 1 = 문구(UTF-8). env NO_COLOR(색만 끔) · PI_ANIM_MAX(초, 안전 상한, 기본 600)
# 쓰기: tty 를 논블로킹으로 열어 터미널이 출력을 안 읽어도(Ctrl+S 등) 막히지 않는다 — 막히면 프레임을 건너뛰고 남은 바이트만 다음 틱에 마저 쓴다(신호도 바로 처리).
# 종료: TERM·INT·HUP = 줄 지우고 커서 복원 후 0 · 부모(pi-edit)가 사라지면 스스로 종료 · 4 = 폭 40칸 미만(그리지 않음 → pi-edit 의 정적 줄 유지) · 3 = 터미널 없음
use strict; use warnings; use utf8;
use Time::HiRes qw(time sleep);
use Fcntl qw(O_WRONLY O_NONBLOCK O_NOCTTY);

sub clean { my $s = shift; $s =~ s/[\x00-\x08\x0b-\x1f\x7f-\x9f]//g; $s }   # 터미널 제어 문자 제거(C0 탭·줄바꿈 제외, DEL, C1) — 라벨에 엔진 이름 등 바깥 글자가 들어와도 화면 시퀀스가 안 되게
my $label = $ARGV[0] // ""; utf8::decode($label);              # Encode 모듈 대신 내장 함수(시작 CPU −12ms 실측)
$label = clean($label); $label =~ s/[\n\t]+/ /g;
sysopen(my $tty, "/dev/tty", O_WRONLY | O_NONBLOCK | O_NOCTTY) or exit 3;
my $pend = "";
sub put { $pend .= $_[0]; my $n = syswrite($tty, $pend); substr($pend, 0, $n, "") if $n }   # 못 쓴 만큼만 남긴다
my $cols;
sub size { my ($r, $c) = split ' ', (`stty size < /dev/tty 2>/dev/null` || "24 80"); $cols = $c || 80 }
size();
exit 4 if $cols < 40;
my $max = $ENV{PI_ANIM_MAX} || 600;
my $ppid = getppid();

# 연필 트랙: W칸. 한 주기 = 쓰기(EASE 프레임) + 다듬기(EASE 프레임) + 반짝 유지(HOLD 프레임) = 28프레임 × 80ms ≈ 2.2초
my $W = 10; my $EASE = 12; my $HOLD = 4;
my ($PEN, $DRAFT, $SPARK) = ("\x{270E}", "\x{223F}", "\x{2726}");                     # ✎ ∿ ✦
my @NEAT = ("\x{203F}", "\x{2040}");                                                 # ‿ ⁀ 번갈아 = 고른 물결
my @pal = (37, 38, 44, 45, 81, 117, 153, 147, 141, 135);                              # 다듬은 줄: 청록 → 보라(아이콘 타일·별빛)
my ($C_PEN, $C_DRAFT, $C_SPARK) = (220, 66, 231);                                      # 노란 연필 · 흐린 청회색 초안 · 흰 별
sub ease { my ($t) = @_; int(($W - 1) * (1 - cos(3.14159265 * $t)) / 2 + 0.5) }         # 양 끝에서 느리고 가운데서 빠른 손놀림
my @track;                                                                            # 프레임 → [[글자, 색] × W]
for my $f (0 .. 2 * $EASE + $HOLD - 1) {
  my @c = map { [" ", 0] } 1 .. $W;
  if ($f < $EASE) {                                                                   # 쓱: 왼→오, 지나간 자리에 초안
    my $p = ease($f / ($EASE - 1));
    $c[$_] = [$DRAFT, $C_DRAFT] for 0 .. $p - 1;
    $c[$p] = [$PEN, $C_PEN];
  } elsif ($f < 2 * $EASE) {                                                          # 싹: 오→왼, 지나간 자리는 다듬은 줄
    my $p = ($W - 1) - ease(($f - $EASE) / ($EASE - 1));
    $c[$_] = [$DRAFT, $C_DRAFT] for 0 .. $p - 1;
    $c[$_] = [$NEAT[$_ % 2], $pal[$_ % @pal]] for $p + 1 .. $W - 1;
    $c[$p] = [$PEN, $C_PEN];
    $c[$W - 1] = [$SPARK, $C_SPARK] if $f == $EASE || $f == $EASE + 1;               # 돌아서는 순간 끝에서 반짝
  } else {                                                                            # 완성: 다듬은 줄 + 연필 끝 반짝
    $c[$_] = [$NEAT[$_ % 2], $pal[$_ % @pal]] for 1 .. $W - 1;
    $c[0] = ($f - 2 * $EASE) % 2 ? [$PEN, $C_PEN] : [$SPARK, $C_SPARK];
  }
  push @track, \@c;
}
my $color = !defined $ENV{NO_COLOR} || $ENV{NO_COLOR} eq "";
my @art = map {                                                                       # 미리 그려 둔 트랙 문자열(색 바뀔 때만 이스케이프)
  my $s = ""; my $cur = -1;
  for my $x (@$_) { if ($color && $x->[1] && $x->[1] != $cur) { $s .= "\e[38;5;$x->[1]m"; $cur = $x->[1] } $s .= $x->[0] }
  $color ? "$s\e[0m" : $s
} @track;

sub width { my $n = 0; for my $c (split //, $_[0]) { $n += $c =~ /[\p{Ea=W}\p{Ea=F}\p{Ea=A}]/ ? 2 : $c =~ /[\p{Mn}\x{FE0F}\x{200D}]/ ? 0 : 1 } $n }
sub fit { my ($s, $m) = @_; return $s if width($s) <= $m; my $r = ""; for my $c (split //, $s) { last if width($r . $c) > $m - 3; $r .= $c } "$r..." }

my $fitted; my $fitcols = 0;
sub frame {
  my ($i, $sec) = @_;
  my $tail = sprintf(" %ds", $sec);
  if ($fitcols != $cols) { $fitted = fit($label, $cols - 1 - $W - 1 - length($tail)); $fitcols = $cols }   # 폭이 바뀔 때만 다시 자름
  my $s = "\r" . $art[$i % @art] . ($color ? " $fitted\e[2m$tail\e[0m" : " $fitted$tail");
  "\e[?2026h$s\e[K\e[?2026l";                                # 동기화 출력(지원 터미널만, 나머지는 무시): 한 프레임을 한 번에 그려 깜빡임 방지
}

my $done = 0;
sub finish { return if $done++; put("\r\e[K\e[?25h"); close $tty; exit 0 }
$SIG{$_} = \&finish for qw(TERM INT HUP);
$SIG{WINCH} = sub { size() };
END { finish() unless $done }
my $t0 = time; my $i = 0; my $hidden = 0; my $next = $t0;
while (1) {
  my $el = time - $t0;
  finish() if $el > $max || getppid() != $ppid;
  if ($cols < 40) { put("\r\e[K\e[?25h") if $hidden; $hidden = 0; sleep 0.5; $next = time; next }   # 실행 중 창이 좁아지면 지우고 멈춤
  if ($pend ne "") { put("") }                              # 이전 프레임이 덜 써졌으면 마저 쓰고 이번 프레임은 건너뜀
  else { my $b = ($hidden ? "" : "\e[?25l") . frame($i, int $el); utf8::encode($b); put($b); $hidden = 1 }   # 커서 숨김(끝나면 복원)
  $i++;
  $next += 0.08; my $d = $next - time;                       # 80ms 간격을 시각 기준으로 맞춘다(작업 시간만큼 밀리지 않게)
  if ($d > 0) { sleep $d } else { $next = time }
}
