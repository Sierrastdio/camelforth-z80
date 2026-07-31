\ =====================================================
\ p(x) = A*x^2 + B*x + C   (저장 순서: addr=A, addr+8=B, addr+16=C)
\ =====================================================

3 CELLS CONSTANT QUAD_BYTES

CREATE P1 QUAD_BYTES ALLOT
CREATE P2 QUAD_BYTES ALLOT
CREATE PR QUAD_BYTES ALLOT

\ ---------- 필드 접근용 헬퍼 (addr -- n / addr n -- ) ----------
: A@ ( addr -- a )        @ ;
: B@ ( addr -- b )        CELL+ @ ;
: C@ ( addr -- c )        2 CELLS + @ ;
: A! ( n addr -- )        ! ;
: B! ( n addr -- )        CELL+ ! ;
: C! ( n addr -- )        2 CELLS + ! ;

: QUAD-CLEAR ( addr -- )
    QUAD_BYTES ERASE ;

: QUAD-SET ( c b a addr -- )
    \ 원래 코드와 동일한 저장 순서 유지: top(a)->addr, b->addr+8, c->addr+16
    DUP >R
    A!          \ a를 addr에 저장 (스택은 A! 안에서 addr 소비하므로 재사용 위해 DUP>R)
    R@ B!
    R> C! ;

: QUAD-PRINT ( addr -- )
    DUP  A@ .
    DUP  B@ .
    C@ .
    CR ;

\ ---------- 다항식 사칙연산: 이름 있는 변수만 사용 ----------
VARIABLE OP1        \ 피연산자1 주소
VARIABLE OP2        \ 피연산자2 주소
VARIABLE OPR        \ 결과 저장 주소

: QUAD-ADD ( p1 p2 pr -- )
    OPR ! OP2 ! OP1 !                   \ OPR! = 최상단인 pr을 꺼내 OPR에 저장. 스택엔 p1, p2만 남음.
                                        \ 그 이후로 OP2에는 p2가, OP1에는 p1이 저장되고 데이터 스택이 빈다.

    OP1 @ A@  OP2 @ A@  +  OPR @ A!     \ OP1 @ 은 OP1에 저장된 'p1의 주소값으로 쓸 데이터'를 D스택으로서 가져옴
                                        \ A@를 통해 OP1 @가 스택에 놓아준 P1의 주소를 전달받아서, 그 주소로 직접 찾아가 진짜 데이터인 A 계수 값을 읽어옴.
                                        \ OP2 @ 를 통해 두번째 식의 a계수를 같은 방식으로 가져온 후 뒤의 +기호를 통해 더한다.
                                        \ OPR @로 OPR 변수 상자를 열어서 결과 다항식이 저장될 PR의 시작 주소값을 꺼내 스택에 놓는다.
                                        \ A!는 스택에서 맨 위의 주소(PR의 주소)와 바로 아래의 값(더한 결과값)을 가져온다.
                                        \ PR의 주소 위치로 찾아가서 더한 결과값을 덮어쓴다.
    OP1 @ B@  OP2 @ B@  +  OPR @ B!
    OP1 @ C@  OP2 @ C@  +  OPR @ C! ;

: QUAD-SUB ( p1 p2 pr -- )
    OPR ! OP2 ! OP1 !
    OP1 @ A@  OP2 @ A@  -  OPR @ A!
    OP1 @ B@  OP2 @ B@  -  OPR @ B!
    OP1 @ C@  OP2 @ C@  -  OPR @ C! ;

VARIABLE SCALE-N

: QUAD-MUL-SCALAR ( p1 n pr -- )
    OPR ! SCALE-N ! OP1 !
    OP1 @ A@  SCALE-N @  *  OPR @ A!
    OP1 @ B@  SCALE-N @  *  OPR @ B!
    OP1 @ C@  SCALE-N @  *  OPR @ C! ;

\ =====================================================
\ (ax^2+bx+c) / (dx+e)  =  q1*x + q0  ... remainder
\ q1 = a / d
\ q0 = (b - q1*e) / d
\ rem = c - q0*e
\ =====================================================

VARIABLE DIV-D       \ 나누는 식의 d
VARIABLE DIV-E       \ 나누는 식의 e
VARIABLE Q1          \ 몫의 x 계수
VARIABLE Q0          \ 몫의 상수항
VARIABLE REM         \ 나머지

: QUAD-DIV ( p1 d e -- )
    DIV-E ! DIV-D ! OP1 !

    OP1 @ A@  DIV-D @  /  Q1 !

    OP1 @ B@  Q1 @  DIV-E @  *  -  DIV-D @  /  Q0 !

    OP1 @ C@  Q0 @  DIV-E @  *  -  REM !

    ." Quotient : "  Q1 @ .  Q0 @ .  CR
    ." Remainder : " REM @ . CR ;


: TEST-QUAD

    CR ." ===== Polynomial Test =====" CR

    2 7 6 P1 QUAD-SET
    1 3 2 P2 QUAD-SET

    ." P1 = " P1 QUAD-PRINT
    ." P2 = " P2 QUAD-PRINT

    P1 P2 PR QUAD-ADD
    ." ADD = " PR QUAD-PRINT

    P1 P2 PR QUAD-SUB
    ." SUB = " PR QUAD-PRINT

    2 7 6 P1 QUAD-SET

    P1 2 PR QUAD-MUL-SCALAR
    ." SCALE = " PR QUAD-PRINT

    ." DIVIDE " P1 QUAD-PRINT  ." / (x+2)" CR
    P1 1 2 QUAD-DIV
;

TEST-QUAD
bye
