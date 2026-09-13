# 화병 상세페이지 자동 출력

`export_all.ps1`은 아래 과정을 한 번에 실행한다.

1. Microsoft Edge로 `index.html`을 860px 너비로 전체 캡처
2. `export_detail.py`로 불필요한 하단 여백 제거
3. 전체 보관용 PNG 생성
4. 쿠팡용 JPG 자동 분할·압축
5. 지정 폴더가 있으면 결과물 복사

## 기본 실행 — 권장

PowerShell에서 다음 명령을 실행한다.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Codex\화병_상세페이지\export_all.ps1"
```

결과물은 기본적으로 아래 폴더에 생성된다.

```text
C:\Codex\화병_상세페이지\export
```

## OneDrive 최종 출력 폴더에 바로 저장

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File "C:\Codex\화병_상세페이지\export_all.ps1" `
  -DestinationPath "C:\Users\dhtng\OneDrive\토끼의 비밀생활\상세페이지\화병\최종 출력"
```

## CMD로 실행

PowerShell 실행 정책 문제를 피하려면 다음 명령도 사용할 수 있다.

```cmd
"C:\Codex\화병_상세페이지\export_all.cmd" -DestinationPath "C:\Users\dhtng\OneDrive\토끼의 비밀생활\상세페이지\화병\최종 출력"
```

## 선택 옵션

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File "C:\Codex\화병_상세페이지\export_all.ps1" `
  -HtmlPath "C:\Codex\화병_상세페이지\index.html" `
  -DestinationPath "저장할 폴더" `
  -Width 860 `
  -CaptureHeight 20000 `
  -WaitMilliseconds 3000
```

HTML이나 CSS를 수정한 뒤 같은 명령을 다시 실행하면 기존 출력 파일이 새 결과로 교체된다.
