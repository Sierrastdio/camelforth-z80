3 CELLS CONSTANT QUAD_BYTES

CREATE P1 QUAD_BYTES ALLOT
CREATE P2 QUAD_BYTES ALLOT
CREATE P3 QUAD_BYTES ALLOT

: QUAD-CLEAR
    QUAD_BYTES ERASE ;

: QUAD-SET ( a b c addr -- )
    >R  ( 첫번째 스택{맨 윗장}을 리턴스택으로 치워둠. ) 
    R@ 2 CELLS + !    ( 리턴 스택에 복사해놓은 첫번째 스택인 addr을 가져옴. addr을 포인터처럼 사용하는게 핵심임.)
      ( 2 CELLS + 는 2셀{16바이트?} 뒤 주소 {c가 들어갈 위치}를 계산.
                    !은 스택의 맨 위의 값을 꺼내 계산된 주소에 저장.)
    R@ 1 CELLS + !
    R> ! ;
( [데이터 스택]                  [실제 메모리 RAM 공간]
|  addr  | ──{포인터 역할}──>  [ addr + 0 ] : a 가 들어갈 방 (1번째
|   c    |                     [ addr + 1CELL ] : b 가 들어갈 방 (2번째
|   b    |                     [ addr + 2CELLS] : c 가 들어갈 방 (3번째
|   a    |)

: QUAD-PRINT 
    DUP @ .     \ 스택 맨 위 주소 [addr이라 지칭.] 복사. 이로써 현재 스택 구성은 addr, addr 해서 두개. @는 fetch이며 맨위{addr}를 꺼내 
                \ 해당 주소에 존재하는 우리가 머릿속에 정해놓은 a를 읽어옴'. 
    DUP 1 CELLS + @ .   \ 또 스택 맨위 주소 복사. 복사된 주소에 1 CELLS{8비트, 다른말로 한 스택 크기만큼.}만큼 더해 b가 될곳의 주소를 만듦. 현재스택구성 [addr].
                        \ @ 를 통해 값을 읽어와 b값을 가져옴. 현재 스택구성 [addr, b] 
                        \ *중요(여담): (DUP) (1 CELLS) (+) 이렇게 끊어 읽으면 편하다!
    2 CELLS + @ .       \ 방금 스택 구성이 [addr, b] 였으니 이미 기존에 쓰던 DUP을 할 필요없음.
    CR ;    \ CR은 줄바꿈을, ;은 단어 정의 종료를 의미.

: QUAD-ADD (p1 p2 pr --)
    >R
    SWAP DUP >R DUP >R
    @ SWAP @ + R@ !
    R> 1 CELLS + SWAP R> 1 CELLS + SWAP
    @ SWAP @ + OVER 1 CELLS + !
    2 CELLS + SWAP 2 CELLS +
    @ SWAP @ + R> 2 CELLS + ! ;

: QUAD-SUB ( p1 p2 pr -- )
    QUAD-CLEAR
    >R OVER @ OVER @ - R@ !
    OVER 1 CELLS + @ OVER 1 CELLS + @ - R@ 1 CELLS + !
    SWAP 2 CELLS + @ SWAP 2 CELLS + @ - R> 2 CELLS + ! ;

: QUAD-MUL-SCALAR ( p1 n pr -- )
    QUAD-CLEAR
    >R
    SWAP DUP >R
    @ OVER * R@ !
    R@ 1 CELLS + @ OVER * R@ 1 CELLS + !
    R> 2 CELLS + @ SWAP * R> 2 CELLS + ! ;

\ ==========================================
\ 4. 다항식 나눗셈 ( ax^2 + bx + c 를 dx + e 로 나눔 )
\ ==========================================
: QUAD-DIV-POLY ( p1 d e -- q1 q0 rem )
    >R >R
    DUP @
    DUP R@ /
    >R
    1 CELLS + @
    R@ R> R@ @ * -
    DUP R@ /
    >R
    SWAP 2 CELLS + @
    R@ R> R> e@ * - \ 주의: 이 부분은 테스트용 의사 코드 로직 포함
    R> DROP R> DROP ;

: QUAD-DIV ( p1 d e -- )
    >R >R
    DUP @ R@ /
    OVER 1 CELLS + @
    OVER R> R@ * -
    R@ /
    ROT 2 CELLS + @
    OVER R> * -
    ." 몫   (q1 x + q0) : " SWAP . . CR
    ." 나머지     (rem) : " . CR ;

\ ==========================================
\ 5. 테스트 실행
\ ==========================================
: TEST-QUAD
    CR ." === 1. 다항식 설정 ===" CR
    2 7 6 P1 QUAD-SET
    ." P1 (2x^2 + 7x + 6) : " P1 QUAD-PRINT

    1 3 2 P2 QUAD-SET
    ." P2 (1x^2 + 3x + 2) : " P2 QUAD-PRINT

    CR ." === 2. 덧셈 및 뺄셈 ===" CR
    P1 P2 PR QUAD-ADD
    ." P1 + P2 : " PR QUAD-PRINT

    P1 P2 PR QUAD-SUB
    ." P1 - P2 : " PR QUAD-PRINT

    CR ." === 3. 나눗셈 ===" CR
    ." (2x^2 + 7x + 6) / (1x + 2) 연산 결과:" CR
    P1 1 2 QUAD-DIV ;

TEST-QUAD
