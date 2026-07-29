\ =====================================================
\ Quad Polynomial Library
\ p(x)=ax²+bx+c
\ =====================================================

3 CELLS CONSTANT QUAD_BYTES

CREATE P1 QUAD_BYTES ALLOT
CREATE P2 QUAD_BYTES ALLOT
CREATE PR QUAD_BYTES ALLOT


: QUAD-CLEAR ( addr -- )
    QUAD_BYTES ERASE ;


: QUAD-SET ( c b a addr -- )

    >R              \ addr을 리턴 스택으로 옮김.

    R@          !   \ 리턴스택에 있는 addr을 '복사'해서 가져와 c를 addr 값 위치에 저장함.
    R@ CELL+    !   \ addr을 또 복사해서 가져옴. 그  addr에 1CELLS만큼 더해서 하나의 스택으로 만듦(addr+8). [a,b,(addr+8)]
                    \ 그리고 b값을 addr로부터 +8인위치에 저장시킴. a,b가 8비트라는 크기 가정하에 b의 주소는 바로 옆(다음)이 됨.
                    \ 이 줄을 마친 스택은 D[a] R[addr] 상태.
    R> 2 CELLS + !  \ 이제 리턴스택의 남은 addr을 '가져와서' c가 a위치의 2CELLS 만큼, 즉 b 바로 옆에 저장되도록 함.
;


: QUAD-PRINT ( addr -- )
    \ @ 연산자는 최상위 스택 값을 메모리 주소로 해석하여 해당 주소에 저장된 값을 읽어오고, 기존의 주소값을 읽어온 데이터 값으로 교체한다.
    DUP @ .         \ addr을 복사하여 addr 주소에 저장된  값을 읽어옴.==> a 값을 읽는거임 -> D[addr, a]이 된다음 맨위 a를 꺼내 밖으로 출력함. 따라서 D[addr]이 된 상태.
    DUP CELL+ @ .   \ D[addr, (addr+8)] 이 되고 addr+8의 위치인 b가 있는곳의 값, 즉 b값을 읽어온다음 이를 출력. 따라서 D[addr]이 된 상태.
    2 CELLS + @ .   \ D[(addr+16)] 되고 addr+16의 위치인 c가 있는곳의 값, 즉 c값을 읽어온다음 이를 출력. 따라서 D[없음].
    CR              \ 줄바꿈 실행.
;


: QUAD-ADD ( p1 p2 pr -- )
    \ note: OVER 연산자는 두번째 스택 값을 복사해서 맨 위에 올림.

    >R              \ D[p1, p2] R[pr]

    \ a
    OVER @          \ D[p1, p2, p1] 이 된후 p1 주소에 있는 데이터값을 읽어와서 맨 위 스택으로 교체함. 최종 D[p1, p2, a1] R[pr]
    OVER @          \ D[p1, p2, a1, p2] 이 된후  p2 주소에 있는 데이터 값을 읽어와서 맨 위 스택으로 교체함. 최종  D[p1, p2, a1, a2] R[pr] 
    +               \ 첫번째 OVER @의 최상위 a1값과 두번째 OVER @의 최상위 값 a2를 더함 -> a1 + a2 그리고 D[p1, p2, (a1+a2)] R[pr]
    R@ !            \ pr을 복사해와 D[p1, p2, (a1+a2), pr] 이 된다음 pr의 값 위치에 a1+a2를 저장함. 최종: D[p1, p2] R[pr]

    \ b
    OVER CELL+ @
    OVER CELL+ @
    +
    R@ CELL+ !

    \ c
    SWAP
    2 CELLS + @

    SWAP
    2 CELLS + @

    +

    R>
    2 CELLS +
    !
;


: QUAD-SUB ( p1 p2 pr -- )

    >R

    \ a
    OVER @
    OVER @
    -
    R@ !

    \ b
    OVER CELL+ @
    OVER CELL+ @
    -
    R@ CELL+ !

    \ c
    SWAP
    2 CELLS + @

    SWAP
    2 CELLS + @

    -

    R>
    2 CELLS +
    !
;


: QUAD-MUL-SCALAR ( p1 n pr -- )

    >R

    OVER @
    OVER *
    R@ !

    OVER CELL+ @
    OVER *
    R@ CELL+ !

    SWAP
    2 CELLS + @

    SWAP
    *

    R>
    2 CELLS +
    !
;


\ =====================================================
\ (ax²+bx+c)/(dx+e)
\ =====================================================

: QUAD-DIV ( p1 d e -- )

    >R               \ e
    >R               \ d

    DUP @
    R@ /
    DUP              \ q1

    OVER CELL+ @
    SWAP
    R@ *
    -
    R@ /
    DUP              \ q0

    ROT
    2 CELLS + @
    SWAP
    R> *
    -
    R> -
    
    ." Quotient : "
    SWAP .
    .

    CR

    ." Remainder : "
    .
    CR
;


: TEST-QUAD

    CR ." ===== Polynomial Test =====" CR

    2 7 6 P1 QUAD-SET
    1 3 2 P2 QUAD-SET

    ." P1 = "
    P1 QUAD-PRINT

    ." P2 = "
    P2 QUAD-PRINT

    P1 P2 PR QUAD-ADD
    ." ADD = "
    PR QUAD-PRINT

    P1 P2 PR QUAD-SUB
    ." SUB = "
    PR QUAD-PRINT

    2 7 6 P1 QUAD-SET

    P1 2 PR QUAD-MUL-SCALAR
    ." SCALE = "
    PR QUAD-PRINT

    ." DIVIDE (2x²+7x+6)/(x+2)" CR
    P1 1 2 QUAD-DIV
;
