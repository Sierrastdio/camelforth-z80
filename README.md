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
