# my Z80 computer project, 'ZF-1'

This fork repo is to port the camelForth language to my Z80 Computer project. <br>
My ROM board is featured 6 of 28C16EEPROM(2KB)s, so I split the compiled binary <br>
into six 2KB chunks. <br>
My Z-80 Computer(ZF-1)s memory map:

| Address Range | Size | Component |
| :--- | :--- | :--- |
| **0000H–07FFH** | 2KB | EEPROM #1 |
| **0800H–0FFFH** | 2KB | EEPROM #2 |
| **1000H–17FFH** | 2KB | EEPROM #3 |
| **1800H–1FFFH** | 2KB | EEPROM #4 |
| **2000H–27FFH** | 2KB | EEPROM #5 |
| **2800H–2FFFH** | 2KB | EEPROM #6 |
| **3000H–3FFFH** | 4KB | Unused |
| **4000H–BFFFH** | 32KB | 62256 RAM |
| **C000H–FFFFH** | 16KB | Unused |

```powershell
cd "C:\Users\sierra\Documents\z88dk-win32-2.4\z88dk\bin"

./z80asm -b -m "C:\Users\sierra\Documents\camelforth-z80\Z80boott.asm"
```

```powershell
# 1. 파일 경로 지정
$bootPath = "C:\Users\sierra\Documents\camelforth-z80\Z80boot.bin"
$camelPath = "C:\Users\sierra\Documents\camelforth-z80\camel80.rom"
$outDir = "C:\Users\sierra\Documents\camelforth-z80"

# 2. 파일 읽기
$boot = $null
$camel = $null

if (Test-Path $bootPath) {
    $boot = [System.IO.File]::ReadAllBytes($bootPath)
    Write-Host "[성공] Z80boot.bin 읽기 완료 ($($boot.Length) 바이트)" -ForegroundColor Cyan
} else {
    Write-Host "[실패] Z80boot.bin 파일을 찾을 수 없습니다: $bootPath" -ForegroundColor Red
}

if (Test-Path $camelPath) {
    $camel = [System.IO.File]::ReadAllBytes($camelPath)
    Write-Host "[성공] camel80.rom 읽기 완료 ($($camel.Length) 바이트)" -ForegroundColor Cyan
} else {
    Write-Host "[실패] camel80.rom 파일을 찾을 수 없습니다: $camelPath" -ForegroundColor Red
}

# 3. 분할 및 파일 생성
if ($boot -ne $null -and $camel -ne $null) {
    # ROM 1 생성
    $rom1 = New-Object byte[] 2048
    [Array]::Copy($boot, 0, $rom1, 0, [Math]::Min(32, $boot.Length))
    $part1Size = [Math]::Min(1984, $camel.Length)
    [Array]::Copy($camel, 0, $rom1, 32, $part1Size)
    [System.IO.File]::WriteAllBytes("$outDir\rom1.bin", $rom1)

    # ROM 2 ~ ROM 6 생성
    $offset = 1984
    for ($i = 2; $i -le 6; $i++) {
        $rom = New-Object byte[] 2048
        if ($offset -lt $camel.Length) {
            $count = [Math]::Min(2048, $camel.Length - $offset)
            [Array]::Copy($camel, $offset, $rom, 0, $count)
            $offset += $count
        }
        [System.IO.File]::WriteAllBytes("$outDir\rom$i.bin", $rom)
    }

    Write-Host "`n[성공] rom1.bin ~ rom6.bin 파일 생성이 완료되었습니다!" -ForegroundColor Green
    Get-ChildItem "$outDir\rom*.bin" | Select-Object Name, Length
}
```

---
---

```powershell
# 21 00 C0(LD HL,$C000)가 그대로 나오는지 확인.
$bytes = [System.IO.File]::ReadAllBytes("camel80.rom")
$bytes[0..31] | ForEach-Object { "{0:X2}" -f $_ }

```


```powershell
#패딩, 분할 단계.
$bytes = [System.IO.File]::ReadAllBytes("camel80.rom")
$padded = New-Object byte[] 12288
[Array]::Copy($bytes, $padded, $bytes.Length)
for ($i = 0; $i -lt 6; $i++) {
    $chunk = $padded[($i*2048)..($i*2048+2047)]
    [System.IO.File]::WriteAllBytes("rom$($i+1).bin", $chunk)
}
```
