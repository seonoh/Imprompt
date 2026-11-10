#!/usr/bin/env perl
# ask-menu.pl — 질문 모드 선택 메뉴(pi-edit 이 부른다). 방향키·숫자·클릭으로 선택지를 고르고, 질문마다 "✎ 직접 입력" 칸에 자유 서술.
# 입력: env PI_MENU_Q(질문 줄들 "N) 질문 [1] a [2] b [3] c"), PI_MENU_HDR("부족한 점: …"), PI_ASK_TIMEOUT(초, 기본 60)
# 출력(stdout 3줄): 결과(enter|skip|timeout) / 답 문자열(질문별 번호 또는 "✎직접 입력"을 " / "로 연결 — pi-edit build_answers 형식) / 화면 요약 1줄
# 종료코드: 0 정상 · 3 질문 파싱 실패·터미널 없음 · 4 화면이 작아 메뉴를 못 그림 → pi-edit 이 한 줄 입력 방식으로 전환 · 5 메뉴 중 터미널이 닫힘(원문 유지)
# 질문은 앞 3개만(ask.md 규칙), 모델이 낸 "직접 입력·기타" 선택지는 숨기고 ✎ 칸으로 대신한다(원래 번호 유지).
# 화면: 대체 화면(vim·less 와 같은 별도 화면)에 그리고 끝나면 원래 화면 복원 — 줄 접힘·밀림이 생기지 않는다.
# 키: ↑↓ 선택 · Tab/→ 다음 질문 · Shift+Tab/← 이전 질문 · 숫자 바로 선택 · 글자 입력 = 직접 입력 · Enter 다음/마지막이면 확정 · Esc 건너뛰기 · 클릭 선택
use strict; use warnings; use utf8;
use Encode qw(decode encode);
use POSIX qw(:termios_h);
use IO::Select;
use Time::HiRes qw(time);

my $timeout = $ENV{PI_ASK_TIMEOUT} || 60;
# 터미널 제어 문자 제거(모델이 낸 질문·선택지·헤더, 사용자가 입력한 글자가 화면 제어 시퀀스가 되지 않게): C0(탭·줄바꿈 제외)·DEL·C1(U+0080-9F). 디코딩된 글자 기준이라 한글은 안 깨진다
sub clean { my $s = shift; $s =~ s/[\x00-\x08\x0b-\x1f\x7f-\x9f]//g; $s }
# 사용자에게 보이는 메뉴 문구(한 곳, ASCII). 질문·선택지·부족한 점 줄은 모델 출력이라 그대로 둔다
my %T = (
  hdr => "Missing details", rec => "  (recommended)", custom => "Custom answer: ",
  confirm => "[ Confirm Enter ]", skip => "[ Skip Esc ]",
  keys => "Up/Down select | Tab/Left/Right switch question | number = pick | type = custom answer | Enter next/confirm | clickable",
  wait => "Waiting for answer %ss | Up/Down select | Tab switch question | Enter next/confirm | Esc skip | clickable",
  summary_custom => "custom: %s",
);
my $hdr = clean(decode("UTF-8", $ENV{PI_MENU_HDR} // ""));
my @Q;
for my $l (split /\n/, clean(decode("UTF-8", $ENV{PI_MENU_Q} // ""))) {
  next unless $l =~ /^\s*\d\)\s*(.*?)\s*\[1\]\s*(.*)$/;
  my $t = $1; my @raw = map { my $x = $_; $x =~ s/^\s+|\s+$//g; $x } split /\[\d\]/, "[1] $2"; shift @raw if @raw && $raw[0] eq "";
  my (@o, @num);                                            # 모델이 낸 "직접 입력·기타" 선택지는 ✎ 칸과 겹치니 숨긴다(원래 번호는 @num 으로 유지)
  for my $k (0 .. $#raw) { next if $raw[$k] eq "" || $raw[$k] =~ /^(직접\s*입력|기타|직접|자유\s*서술|other)\b/i; push @o, $raw[$k]; push @num, $k + 1 }
  push @Q, { t => $t, o => \@o, n => \@num } if @o;
  last if @Q == 3;                                          # 질문은 최대 3개(ask.md 규칙) — 넘치면 앞 3개만
}
exit 3 unless @Q;
open(my $tty, "+<", "/dev/tty") or exit 3;
my $fd = fileno($tty);
my ($rows, $cols) = split ' ', (`stty size < /dev/tty 2>/dev/null` || "24 80");
$rows ||= 24; $cols ||= 80;
my $need = 4 + 2;                                           # 부족한 점·빈 줄 + 버튼·상태
$need += 2 + scalar(@{ $_->{o} }) + 1 for @Q;               # 질문 줄 + 선택지 + 직접 입력 + 빈 줄
exit 4 if $rows < $need || $cols < 40;

my $term = POSIX::Termios->new; $term->getattr($fd) or exit 3;
my ($lflag, $iflag, $vmin, $vtime) = ($term->getlflag, $term->getiflag, $term->getcc(VMIN), $term->getcc(VTIME));
my $done = 0; my $raw = 0;                                   # raw 모드에 들어간 뒤에만 복원
sub out { print $tty encode("UTF-8", join "", @_) }
sub restore {
  return if !$raw || $done++;
  out("\e[?1000l\e[?1006l\e[?25h\e[?1049l");
  $term->setlflag($lflag); $term->setiflag($iflag); $term->setcc(VMIN, $vmin); $term->setcc(VTIME, $vtime); $term->setattr($fd, TCSANOW);
}
$SIG{$_} = sub { restore(); binmode STDOUT, ":utf8"; print "eof\n\n\n"; exit 5 } for qw(INT TERM HUP);   # 터미널 끊김·종료 신호 → 원문 유지
END { restore() }
$term->setlflag($lflag & ~(ECHO | ICANON | ISIG | IEXTEN)); $term->setiflag($iflag & ~(IXON | ICRNL));
$term->setcc(VMIN, 1); $term->setcc(VTIME, 0); $term->setattr($fd, TCSANOW); $raw = 1;
out("\e[?1049h\e[?25l\e[?1000h\e[?1006h");                 # 대체 화면·커서 숨김·마우스 클릭 보고(SGR)

sub width { my $n = 0; for my $c (split //, $_[0]) { $n += $c =~ /[\p{Ea=W}\p{Ea=F}\p{Ea=A}]/ ? 2 : $c =~ /[\p{Mn}\x{FE0F}\x{200D}]/ ? 0 : 1 } $n }
sub fit { my ($s, $max) = @_; return $s if width($s) <= $max; my $r = ""; for my $c (split //, $s) { last if width($r . $c) > $max - 3; $r .= $c } "$r..." }

my @sel = (0) x @Q; my @free = ("") x @Q; my $cq = 0; my $started = 0; my $deadline = time + $timeout; my %rowmap;
sub nopt { scalar @{ $Q[$_[0]]{o} } }                       # 직접 입력 = 인덱스 nopt
sub render {
  my @L; %rowmap = ();
  push @L, $hdr ne "" ? $hdr : $T{hdr}, "";
  for my $i (0 .. $#Q) {
    my $on = $i == $cq;
    push @L, ($on ? "▶ " : "  ") . ($i + 1) . ") " . $Q[$i]{t};
    for my $j (0 .. nopt($i)) {
      my $cur = ($on && $sel[$i] == $j) ? "❯" : " "; my $rad = $sel[$i] == $j ? "(*)" : "( )";
      my $txt = $j < nopt($i) ? ($j + 1) . ". " . $Q[$i]{o}[$j] . ($j == 0 ? $T{rec} : "")
                              : $T{custom} . $free[$i] . (($on && $sel[$i] == $j) ? "▏" : "");
      $rowmap{ scalar(@L) + 1 } = [$i, $j]; push @L, "   $cur $rad $txt";
    }
    push @L, "";
  }
  my ($b1, $gap, $b2) = ($T{confirm}, "     ", $T{skip});   # 같은 줄의 두 버튼 — 가로 칸 범위로 구분
  my $x1 = 3; my $x2 = $x1 + width($b1) + width($gap);
  $rowmap{ scalar(@L) + 1 } = ["btn", $x1, $x1 + width($b1) - 1, $x2, $x2 + width($b2) - 1]; push @L, "  $b1$gap$b2";
  my $left = int($deadline - time + 0.999); $left = 0 if $left < 0;
  push @L, $started ? $T{keys} : sprintf($T{wait}, $left);
  out("\e[H\e[2J", join("\r\n", map { fit($_, $cols - 2) } @L));
}
sub finish {
  my $how = shift; restore();
  my (@a, @s);
  for my $i (0 .. $#Q) {
    if ($sel[$i] == nopt($i)) {
      my $f = $free[$i]; $f =~ s/^\s+|\s+$//g; $f =~ s{\s*/\s*}{/}g;
      if ($f eq "") { push @a, $Q[$i]{n}[0]; push @s, $Q[$i]{o}[0] } else { push @a, "✎$f"; push @s, sprintf($T{summary_custom}, $f) }   # ✎ 표식 = 직접 입력(숫자만 적어도 선택지 번호로 바뀌지 않게)
    } else { push @a, $Q[$i]{n}[ $sel[$i] ]; push @s, $Q[$i]{o}[ $sel[$i] ] }
  }
  binmode STDOUT, ":utf8";
  print "$how\n", ($how eq "enter" ? join(" / ", @a) : ""), "\n", join(" · ", @s), "\n";
  exit 0;
}
sub start { $started = 1 }
sub key {
  my $k = shift; start();
  my $n = nopt($cq); my $editing = $sel[$cq] == $n;
  if    ($k eq "up")    { $sel[$cq] = ($sel[$cq] - 1) % ($n + 1) }
  elsif ($k eq "down")  { $sel[$cq] = ($sel[$cq] + 1) % ($n + 1) }
  elsif ($k eq "next")  { $cq = ($cq + 1) % @Q }
  elsif ($k eq "prev")  { $cq = ($cq - 1) % @Q }
  elsif ($k eq "enter") { $cq < $#Q ? $cq++ : finish("enter") }
  elsif ($k eq "skip")  { finish("skip") }
  elsif ($k eq "bs")    { chop $free[$cq] if $editing }
  elsif ($k =~ /^c:(.)$/s) {
    my $c = clean($1);
    if (!$editing && $c =~ /^[1-9]$/) { if ($c <= $n) { $sel[$cq] = $c - 1; $cq++ if $cq < $#Q } }
    elsif ($editing || $c =~ /\S/) { $sel[$cq] = $n; $free[$cq] .= $c }
  }
}
sub click {
  my ($b, $x, $y) = @_; start();
  if ($b == 64) { return key("up") } if ($b == 65) { return key("down") }
  return unless $b == 0;
  my $m = $rowmap{$y} or return;
  if ($m->[0] eq "btn") {
    return finish("enter") if $x >= $m->[1] && $x <= $m->[2];
    return finish("skip")  if $x >= $m->[3] && $x <= $m->[4];
    return;
  }
  ($cq, $sel[ $m->[0] ]) = @$m;
}

my $sel_io = IO::Select->new($tty); my $buf = "";
render();
while (1) {
  if (!$started && time >= $deadline) { finish("timeout") }
  my $wait = $started ? 1 : ($deadline - time < 1 ? $deadline - time : 1); $wait = 0.05 if $wait < 0.05;
  if ($sel_io->can_read($wait)) {
    my $got = sysread($tty, my $raw, 256);
    unless ($got) { restore(); binmode STDOUT, ":utf8"; print "eof\n\n\n"; exit 5 }   # 터미널이 닫힘 → 아무도 없으니 pi-edit 이 원문 유지로 끝낸다
    $buf .= $raw;
    while (length $buf) {
      if ($buf =~ /^\e(?:\[[<0-9;]*|O)?$/) {                 # 단독 Esc 인지, 방향키·클릭 시퀀스가 덜 온 것인지 50ms 더 본다
        if ($sel_io->can_read(0.05)) { sysread($tty, my $more, 256); $buf .= $more; next }
        $buf = ""; key("skip"); last;
      }
      if ($buf =~ s/^\e\[<(\d+);(\d+);(\d+)([Mm])//) { click($1, $2, $3) if $4 eq "M"; next }
      if ($buf =~ s/^\e(?:\[|O)([ABCDZ])//) { key({ A => "up", B => "down", C => "next", D => "prev", Z => "prev" }->{$1}); next }
      if ($buf =~ s/^\e\[[0-9;]*[~A-Za-z]//) { next }        # 그 밖의 제어 시퀀스는 무시
      if ($buf =~ s/^\e//) { key("skip"); next }
      if ($buf =~ s/^[\r\n]//) { key("enter"); next }
      if ($buf =~ s/^\t//) { key("next"); next }
      if ($buf =~ s/^[\x7f\x08]//) { key("bs"); next }
      if ($buf =~ s/^[\x03]//) { key("skip"); next }         # Ctrl+C = 건너뛰기(원문 보존)
      if ($buf =~ s/^[\x00-\x1f]//) { next }
      $buf =~ s/^([^\x00-\x1f\x7f]+)// or last;              # 다음 제어 문자(Enter·Esc·Tab·Backspace) 전까지의 글자만 — 같은 덩어리로 온 Enter 를 글자로 먹지 않게
      my $run = $1; my $ch = decode("UTF-8", $run, Encode::FB_QUIET);   # 완성된 글자만 꺼내고, 덜 온 바이트는 버퍼 앞에 되돌려 다음 읽기에 이어 붙인다
      $buf = $run . $buf;
      last if $ch eq "";
      key("c:$_") for split //, $ch;
    }
  }
  render();
}
