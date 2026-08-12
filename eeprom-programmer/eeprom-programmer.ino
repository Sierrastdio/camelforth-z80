/*
 * 28C16 EEPROM 프로그래머 (시리얼, 시작주소/길이 지정 가능)
 * ============================================================
 * 2048바이트 전체를 무조건 0번지부터 쓰는 게 아니라,
 * 호스트가 "이 주소부터 이만큼 써라"를 지정할 수 있다.
 * 서로 다른 파일(예: 부트스트랩 32바이트 @0000H, camelForth 5787바이트
 * @0020H)을 같은 칩(혹은 여러 칩)에 나눠서 여러 번 전송해 이어붙일 수 있음.
 *
 * 프로토콜:
 *   호스트 -> 아두이노 : "W <시작주소hex> <길이dec>\n"
 *                        예) "W 0000 32\n"  또는  "W 0800 2048\n"
 *   아두이노 -> 호스트 : "READY"
 *   -- 이후 길이만큼, 바이트 하나마다 --
 *   호스트 -> 아두이노 : 데이터 1바이트
 *   아두이노 -> 호스트 : 0x06 (ACK, 이 바이트 다 구웠음. 128바이트마다 "." 도 추가)
 *   -- 흐름제어: Uno의 RX버퍼(64B)가 작고 쓰기(delay 10ms)가 느려서,
 *      한번에 몰아 보내면 버퍼 오버플로우로 바이트가 유실된다.
 *      그래서 반드시 ACK 받은 뒤에만 다음 바이트를 보내야 한다. --
 *   아두이노 -> 호스트 : 다 쓰면 "END <종료주소hex>"  (다음에 이어 쓸 빈 주소)
 *                        readback 덤프 (시작~종료 구간만)
 *                        "DONE"
 *   에러 시                "ERROR: <사유>"
 *
 * 시작주소+길이가 ROM_SIZE(2048, 28C16 기준)를 넘으면 즉시 에러 처리.
 */

#define SHIFT_DATA   2
#define SHIFT_CLK    3
#define SHIFT_LATCH  4
#define EEPROM_D0    5
#define EEPROM_D7    12
#define WRITE_EN     13

#define ROM_SIZE        2048   // 28C16 = 2KB. 다른 칩 쓰면 여기만 바꾸면 됨
#define SERIAL_BAUD     57600
#define BYTE_TIMEOUT_MS 5000
#define LINE_BUF_SIZE   32

/*
 * Output the address bits and outputEnable signal using shift registers.
 */
void setAddress(int address, bool outputEnable) {
  shiftOut(SHIFT_DATA, SHIFT_CLK, MSBFIRST, (address >> 8) | (outputEnable ? 0x00 : 0x80));
  shiftOut(SHIFT_DATA, SHIFT_CLK, MSBFIRST, address);
  digitalWrite(SHIFT_LATCH, LOW);
  digitalWrite(SHIFT_LATCH, HIGH);
  digitalWrite(SHIFT_LATCH, LOW);
}

byte readEEPROM(int address) {
  for (int pin = EEPROM_D0; pin <= EEPROM_D7; pin += 1) {
    pinMode(pin, INPUT);
  }
  setAddress(address, /*outputEnable*/ true);
  byte data = 0;
  for (int pin = EEPROM_D7; pin >= EEPROM_D0; pin -= 1) {
    data = (data << 1) + digitalRead(pin);
  }
  return data;
}

void writeEEPROM(int address, byte data) {
  setAddress(address, /*outputEnable*/ false);
  for (int pin = EEPROM_D0; pin <= EEPROM_D7; pin += 1) {
    pinMode(pin, OUTPUT);
  }
  for (int pin = EEPROM_D0; pin <= EEPROM_D7; pin += 1) {
    digitalWrite(pin, data & 1);
    data = data >> 1;
  }
  digitalWrite(WRITE_EN, LOW);
  delayMicroseconds(1);
  digitalWrite(WRITE_EN, HIGH);
  delay(10);
}

bool readSerialByte(byte *out) {
  unsigned long start = millis();
  while (!Serial.available()) {
    if (millis() - start > BYTE_TIMEOUT_MS) return false;
  }
  *out = (byte)Serial.read();
  return true;
}

// 개행까지 한 줄을 읽어 buf에 담는다 (커맨드 라인 파싱용). 성공 시 true.
bool readCommandLine(char *buf, size_t bufsize, unsigned long timeout_ms) {
  size_t idx = 0;
  unsigned long start = millis();
  while (millis() - start < timeout_ms) {
    if (Serial.available()) {
      char c = (char)Serial.read();
      if (c == '\n') {
        buf[idx] = '\0';
        return true;
      }
      if (c != '\r' && idx < bufsize - 1) {
        buf[idx++] = c;
      }
      start = millis();  // 문자 오는 동안은 타임아웃 연장
    }
  }
  buf[idx] = '\0';
  return false;
}

void printRange(int start_addr, int length) {
  int end_addr = start_addr + length;
  // 16바이트 정렬 경계로 스냅해서 보기 좋게 덤프 (범위를 살짝 넓혀서 출력)
  int dump_start = start_addr - (start_addr % 16);
  for (int base = dump_start; base < end_addr; base += 16) {
    byte data[16];
    for (int offset = 0; offset <= 15; offset += 1) {
      int a = base + offset;
      data[offset] = (a < ROM_SIZE) ? readEEPROM(a) : 0x00;
    }
    char buf[80];
    sprintf(buf, "%03x:  %02x %02x %02x %02x %02x %02x %02x %02x   %02x %02x %02x %02x %02x %02x %02x %02x",
            base, data[0], data[1], data[2], data[3], data[4], data[5], data[6], data[7],
            data[8], data[9], data[10], data[11], data[12], data[13], data[14], data[15]);
    Serial.println(buf);
  }
}

// "W <hexaddr> <declen>" 커맨드를 처리한다.
void handleWriteCommand(const char *cmdline) {
  unsigned int start_addr = 0;
  unsigned int length = 0;

  // "W " 다음부터 파싱
  if (sscanf(cmdline, "W %x %u", &start_addr, &length) != 2) {
    Serial.println("ERROR: BAD COMMAND");
    return;
  }

  if (start_addr >= ROM_SIZE || length == 0 || (start_addr + length) > ROM_SIZE) {
    Serial.print("ERROR: RANGE OUT OF BOUNDS (start=0x");
    Serial.print(start_addr, HEX);
    Serial.print(", len=");
    Serial.print(length);
    Serial.print(", ROM_SIZE=");
    Serial.print(ROM_SIZE);
    Serial.println(")");
    return;
  }

  Serial.println("READY");

  // [수정] 바이트 단위 ACK 흐름제어.
  // Uno의 하드웨어 RX버퍼는 64바이트뿐인데 writeEEPROM 1회에 약 10ms(delay)가
  // 걸려서 초당 100바이트 정도밖에 못 받는다. 호스트가 2048바이트를 한번에
  // 쏟아부으면 버퍼가 넘쳐서 중간 바이트가 유실되고, 그 뒤로 수신 위치가
  // 어긋나 영원히 안 올 바이트를 기다리다 타임아웃이 난다.
  // -> 한 바이트 받고 굽고 나서 ACK(0x06)를 보내고, 호스트는 그 ACK을 받은
  //    뒤에야 다음 바이트를 보내도록 해서 Arduino 처리 속도에 맞춘다.
  for (unsigned int i = 0; i < length; i++) {
    byte b;
    if (!readSerialByte(&b)) {
      Serial.println("ERROR: TIMEOUT");
      return;
    }
    writeEEPROM(start_addr + i, b);
    Serial.write((byte)0x06);   // ACK: 이 바이트 다 구웠다, 다음 바이트 보내도 됨
    if (i % 128 == 0) Serial.print(".");
  }
  Serial.println();
  Serial.println("write done");

  unsigned int end_addr = start_addr + length;  // 다음에 이어 쓸 주소
  char endbuf[24];
  sprintf(endbuf, "END %04x", end_addr);
  Serial.println(endbuf);

  Serial.println("Reading back for verification:");
  printRange(start_addr, length);

  Serial.println("DONE");
}

void setup() {
  pinMode(SHIFT_DATA, OUTPUT);
  pinMode(SHIFT_CLK, OUTPUT);
  pinMode(SHIFT_LATCH, OUTPUT);
  digitalWrite(WRITE_EN, HIGH);
  pinMode(WRITE_EN, OUTPUT);

  Serial.begin(SERIAL_BAUD);
  while (!Serial) { }

  while (Serial.available()) Serial.read();

  Serial.println("READY");   // 부팅 직후에도 명령을 받을 수 있음을 알림
}

void loop() {
  char line[LINE_BUF_SIZE];
  if (Serial.available()) {
    if (readCommandLine(line, sizeof(line), BYTE_TIMEOUT_MS)) {
      if (line[0] == 'W' || line[0] == 'w') {
        handleWriteCommand(line);
      } else if (line[0] == 'r' || line[0] == 'R') {
        // 하위호환: 예전 스크립트가 'r' 한글자만 보내는 경우 대비
        Serial.println("READY");
      } else if (strlen(line) > 0) {
        Serial.println("ERROR: UNKNOWN COMMAND");
      }
    } else {
      Serial.println("ERROR: TIMEOUT");
    }
  }
}
