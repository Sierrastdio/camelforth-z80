#!/usr/bin/env python3
"""
Serial Uploader for Arduino-based EEPROM programmer.
============================================================

    w <file_name.bin>                 -> it will write the file to the next available address (auto-append)
                                        
    w <file_name.bin> <start_address_hex>
                                        ex) w boot.bin 0000
                                            w camel80.bin 0020
use "q" or Ctrl+C to quit the program.
"""

import sys
import time
import glob

try:
    import serial
except ImportError:
    print("need pyserial: pip install pyserial")
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
    
    while True:
        prompt = f"Serial port [{default}]: " if default else "Serial port (e.g., COM3, /dev/ttyUSB0): "
        port = input(prompt).strip() or default
        
        if not port:
            print("Error: Port name cannot be empty. Please try again.\n")
            continue

        try:
            ser = serial.Serial(port, BAUD, timeout=0.2)
            print(f"{port} @ {BAUD}bps connected. Waiting for Arduino reset...")
            time.sleep(2.0)
            ser.reset_input_buffer()
            return ser
        except serial.SerialException as e:
            print(f"Error: Could not open port '{port}' ({e}). Please try again.\n")
            # 연결 실패 시 디폴트 포트 재검색
            default = find_default_port()


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
        print(f"  <Arduino> {line}")
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
        print(f"Cannot open file: {e}")
        return None

    length = len(data)
    if length == 0:
        print("File is empty.")
        return None

    ser.reset_input_buffer()

    cmd = f"W {start_addr:04x} {length}\n"
    print(f"Sending command: {cmd.strip()}  (start address=0x{start_addr:04x}, length={length})")
    ser.write(cmd.encode("ascii"))
    ser.flush()

    # READY 대기
    deadline = time.time() + READY_TIMEOUT
    ready = False
    while time.time() < deadline:
        line = read_line(ser, timeout=0.5)
        if line is None:
            continue
        print(f"  <Arduino> {line}")
        if line.startswith("ERROR"):
            print("Arduino rejected the command.")
            return None
        if "READY" in line:
            ready = True
            break
    if not ready:
        print("Error: Failed to receive READY signal.")
        return None

    print(f"{filename} ({length} bytes) transmission started (ACK flow control per byte)...")

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
            try:
                sys.stdout.write(b.decode(errors="replace"))
                sys.stdout.flush()
            except Exception:
                pass
        if not acked:
            print(f"\nError: {i}th byte({i} of {length}) ACK timeout. Transmission aborted.")
            return None

    print()
    end_addr = None
    while True:
        line = read_line(ser, timeout=BYTE_TIMEOUT)
        if line is None:
            print("Error: Response timeout during writing.")
            return None
        print(f"  <Arduino> {line}")
        if line.startswith("ERROR"):
            print("Arduino reported an error. Programming failed.")
            return None
        if line.startswith("END "):
            try:
                end_addr = int(line.split()[1], 16)
            except (IndexError, ValueError):
                pass
        if line.strip() == "DONE":
            break

    if end_addr is None:
        print("Warning: Failed to receive end address (END). Specify address manually for next write.")
        return None

    print(f"Writing completed. Next empty address = 0x{end_addr:04x}")

    return end_addr


def main():
    print(__doc__)
    ser = open_serial()

    print("Arduino booting verification(press arudino reset button)...")
    if not wait_for_boot_ready(ser):
        print("Warning: Failed to receive READY signal after boot. Continuing...")
    next_addr = 0x0000  # Session-level automatic continuation cursor

    try:
        while True:
            try:
                cmd = input(f"\n[Next automatic start address: 0x{next_addr:04x}] > ").strip()
            except EOFError:
                break

            if not cmd:
                continue
            if cmd in ("q", "quit", "exit"):
                break

            parts = cmd.split()
            if parts[0] != "w" or len(parts) not in (2, 3):
                print("Usage: w <filename.bin> [start_address hex]   (exit: q)")
                continue

            filename = parts[1].strip().strip('"').strip("'")
            if len(parts) == 3:
                try:
                    start_addr = int(parts[2], 16)
                except ValueError:
                    print("Start address must be a hexadecimal number (e.g., 0020)")
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
        print("\nExiting.")


if __name__ == "__main__":
    main()