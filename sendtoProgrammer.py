#!/usr/bin/env python3
"""
EEPROM 프로그래머 호스트 스크립트 (시작주소 지정 지원)
============================================================
실행 후 프롬프트에서:

    w <파일명.bin>                 -> 이전에 쓴 자리(END 주소) 바로 뒤에 이어서 씀
                                       (세션 처음이면 0000H부터)
    w <파일명.bin> <시작주소hex>    -> 지정한 주소부터 씀
                                       예) w boot.bin 0000
                                           w camel80.bin 0020

한 칩 안에 서로 다른 파일(부트스트랩 + camelForth 본체 등)을
순서대로 이어붙여 구울 때 쓴다. 매 전송마다 아두이노가 돌려주는
"END <주소>"를 기억해뒀다가 다음 w에 시작주소를 안 주면 자동으로 이어쓴다.

종료: q 또는 Ctrl+C
"""

import sys
import time
import glob

try:
    import serial
except ImportError:
    print("pyserial이 필요합니다: pip install pyserial")
    sys.exit(1)

BAUD = 57600
READY_TIMEOUT = 10.0
BYTE_TIMEOUT = 5.0
LINE_TIMEOUT = 3.0


def find_default_port():
    candidates = []
    candidates += glob.glob("/dev/ttyUSB*")
    candidates += glob.glob("/dev/ttyACM*")
    candidates += glob.glob("/dev/cu.usbserial*")
    candidates += glob.glob("/dev/cu.usbmodem*")
    candidates += glob.glob("/dev/cu.wchusbserial*")
    return candidates[0] if candidates else None


def open_serial():
    default = find_default_port()
    prompt = f"시리얼 포트 [{default}]: " if default else "시리얼 포트 (예: COM3, /dev/ttyUSB0): "
    port = input(prompt).strip() or default
    if not port:
        print("포트를 지정해야 합니다.")
        sys.exit(1)

    ser = serial.Serial(port, BAUD, timeout=0.2)
    print(f"{port} @ {BAUD}bps 연결됨. 아두이노 리셋 대기 중...")
    time.sleep(2.0)
    ser.reset_input_buffer()
    return ser


def read_line(ser, timeout=LINE_TIMEOUT):
    deadline = time.time() + timeout
    buf = bytearray()
    while time.time() < deadline:
        chunk = ser.read(1)
        if chunk:
            if chunk == b"\n":
                return buf.decode(errors="replace").rstrip("\r")
            buf += chunk
        else:
            if buf:
                deadline = time.time() + timeout
    return buf.decode(errors="replace") if buf else None


def wait_for_boot_ready(ser, timeout=READY_TIMEOUT):
    """전원 인가/리셋 직후 아두이노가 보내는 최초 READY를 대기."""
    deadline = time.time() + timeout
    while time.time() < deadline:
        line = read_line(ser, timeout=0.5)
        if line is None:
            continue
        print(f"  <아두이노> {line}")
        if "READY" in line:
            return True
    return False


def parse_dump_line(line):
    line = line.strip()
    if ":" not in line:
        return None
    addr_part, rest = line.split(":", 1)
    try:
        base = int(addr_part.strip(), 16)
    except ValueError:
        return None
    hex_bytes = rest.split()
    if not hex_bytes:
        return None
    try:
        values = [int(h, 16) for h in hex_bytes]
    except ValueError:
        return None
    return base, values


def program_file(ser, filename, start_addr):
    try:
        with open(filename, "rb") as f:
            data = f.read()
    except OSError as e:
        print(f"파일을 열 수 없습니다: {e}")
        return None

    length = len(data)
    if length == 0:
        print("빈 파일입니다.")
        return None

    ser.reset_input_buffer()

    cmd = f"W {start_addr:04x} {length}\n"
    print(f"명령 전송: {cmd.strip()}  (시작주소=0x{start_addr:04x}, 길이={length})")
    ser.write(cmd.encode("ascii"))
    ser.flush()

    # READY 대기
    deadline = time.time() + READY_TIMEOUT
    ready = False
    while time.time() < deadline:
        line = read_line(ser, timeout=0.5)
        if line is None:
            continue
        print(f"  <아두이노> {line}")
        if line.startswith("ERROR"):
            print("아두이노가 명령을 거부했습니다.")
            return None
        if "READY" in line:
            ready = True
            break
    if not ready:
        print("오류: READY 신호를 받지 못했습니다.")
        return None

    print(f"{filename} ({length}바이트) 전송 시작 (바이트당 ACK 흐름제어)...")

    # [수정] 한번에 다 쏟아붓지 않고, 바이트 하나 보낼 때마다 아두이노의
    # ACK(0x06)를 기다렸다가 다음 바이트를 보낸다. Uno의 작은 RX버퍼와
    # 느린 쓰기 사이클(10ms/byte) 때문에 미리 흐름제어 없이 몰아보내면
    # 버퍼 오버플로우로 바이트가 유실되어 이후 통신이 영구히 어긋난다.
    ACK = b"\x06"
    for i, byte_val in enumerate(data):
        ser.write(bytes([byte_val]))
        ser.flush()

        deadline = time.time() + BYTE_TIMEOUT
        acked = False
        while time.time() < deadline:
            b = ser.read(1)
            if not b:
                continue
            if b == ACK:
                acked = True
                break
            # ACK이 아닌 바이트(진행 표시 "." 등)는 그냥 흘려보여준다
            try:
                sys.stdout.write(b.decode(errors="replace"))
                sys.stdout.flush()
            except Exception:
                pass
        if not acked:
            print(f"\n오류: {i}번째 바이트({i} of {length}) ACK 타임아웃. 전송 중단.")
            return None

    print()
    end_addr = None
    while True:
        line = read_line(ser, timeout=BYTE_TIMEOUT)
        if line is None:
            print("오류: 쓰기 진행 중 응답 타임아웃.")
            return None
        print(f"  <아두이노> {line}")
        if line.startswith("ERROR"):
            print("아두이노 쪽에서 에러를 보고했습니다. 굽기 실패.")
            return None
        if line.startswith("END "):
            try:
                end_addr = int(line.split()[1], 16)
            except (IndexError, ValueError):
                pass
        if line.strip() == "DONE":
            break

    if end_addr is None:
        print("경고: 종료주소(END)를 받지 못했습니다. 다음 이어쓰기는 수동으로 주소를 지정하세요.")
        return None

    print(f"쓰기 완료. 다음 빈 주소 = 0x{end_addr:04x}")

    # 방금 받은 응답 중 readback 덤프를 이미 화면에 출력했으므로,
    # 여기서는 별도 파싱 없이 END 주소만 반환 (검증은 화면 출력으로 육안 확인,
    # 필요하면 재요청해서 자동비교하는 기능을 추가할 수 있음)
    return end_addr


def main():
    print(__doc__)
    ser = open_serial()

    print("아두이노 부팅 확인 중...")
    if not wait_for_boot_ready(ser):
        print("경고: 부팅 직후 READY를 못 받았습니다. 이미 대기 상태일 수 있으니 계속 진행합니다.")

    next_addr = 0x0000  # 세션 내 자동 이어쓰기용 커서

    try:
        while True:
            try:
                cmd = input(f"\n[다음 자동시작주소: 0x{next_addr:04x}] > ").strip()
            except EOFError:
                break

            if not cmd:
                continue
            if cmd in ("q", "quit", "exit"):
                break

            parts = cmd.split()
            if parts[0] != "w" or len(parts) not in (2, 3):
                print("사용법: w <파일명.bin> [시작주소hex]   (종료: q)")
                continue

            filename = parts[1].strip().strip('"').strip("'")
            if len(parts) == 3:
                try:
                    start_addr = int(parts[2], 16)
                except ValueError:
                    print("시작주소는 16진수로 입력하세요 (예: 0020)")
                    continue
            else:
                start_addr = next_addr

            result = program_file(ser, filename, start_addr)
            if result is not None:
                next_addr = result
    except KeyboardInterrupt:
        pass
    finally:
        ser.close()
        print("\n종료합니다.")


if __name__ == "__main__":
    main()
