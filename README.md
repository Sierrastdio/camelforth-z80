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