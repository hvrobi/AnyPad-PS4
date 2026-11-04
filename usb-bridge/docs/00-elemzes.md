# AnyPad USB Bridge – 0. fázis: forráskód- és hardverarchitektúra-elemzés

Állapot: 0. fázis, termékkód nélkül. Dátum: 2026-11-04.

## Jelölések és alapelvek

- **[T]** forrásból vagy dokumentációból igazolt tény (fájl:sor vagy URL).
- **[V]** valószínű technikai lehetőség (a forrásból következik, de nincs kipróbálva).
- **[E]** még ellenőrizendő feltételezés.

Banana Pro-n és PS4-en semmit nem próbáltam ki, ilyen hozzáférésem nincs. Minden
hardveres állítás [V] vagy [E], kivéve, ahol a kernel forráskódja vagy a devicetree
közvetlenül igazolja; ilyenkor is csak annyi a [T], amit a forrás állít, és nem az,
hogy a táblán így működik.

### A források helye és elérhetősége

A feladat `forras/` mappát említ. Ilyen mappa nincs: a három forrás külön git-repóként
volt jelen a munkakörnyezetben (`/home/user/<repo>`). Az elemzett állapotok [T]:

| Repó | Elemzett tükör | Commit |
|---|---|---|
| AnyPad-PS4 (upstream: github.com/Vld439/AnyPad-PS4) | github.com/hvrobi/AnyPad-PS4 | `2556e693458b5e9b06485aa934da74e6e0c26535` (0.2.2-beta) |
| rpi-dualsense-ps4-bridge (upstream: github.com/ShubhxYT/rpi-dualsense-ps4-bridge) | github.com/hvrobi/rpi-dualsense-ps4-bridge | `2945043fdf6bc914b200e3aec82a4031501fe827` |
| ffsds4 (upstream: github.com/dogtopus/ffsds4) | github.com/hvrobi/ffsds4 | `0827203660f59dfa80e36f9accf4aef0ea90a05e`, vagyis pontosan a hídprojektben rögzített commit |

**Az `ffsds4` elérhető volt, ezért az A) feladat teljes.** Hogy a `hvrobi/*` tükrök
megegyeznek-e az upstream repókkal, nem ellenőriztem [E].

Kiegészítő források (csak olvasásra töltöttem le őket, semmit nem telepítettem):

- `python-functionfs` 0.9.2 forrása (PyPI sdist). Az `ffsds4` erre épül, és a
  gadget/UDC-kezelés nem az `ffsds4`-ben, hanem ebben van.
- A Linux mainline (`torvalds/linux`, `master`, 2026-11-04-i állapot) fájljai:
  `drivers/usb/musb/sunxi.c`, `drivers/phy/allwinner/phy-sun4i-usb.c`,
  `arch/arm/boot/dts/allwinner/sun7i-a20.dtsi`, `sun7i-a20-bananapro.dts`.
- Az Armbian build `config/boards/bananapipro.csc` és `config/sources/families/sun7i.conf` fájlja.
- **Nem érhettem el** a linux-sunxi.org wikit, a docs.armbian.com-ot és a gp2040-ce.info-t:
  a munkakörnyezet hálózati szabályai tiltják ezeket. Az innen származó korábbi
  megállapítások ezért [E] jelölésűek maradnak.

Lefuttatott, csak számítógépes tesztek (hardveres bizonyítéknak egyik sem számít):

- Hídprojekt: `PYTHONPATH=bridge:dashboard python3 -m unittest discover -s tests`, eredmény
  **35 teszt, OK** [T].
- AnyPad: `make test`, eredmény **6 tesztprogram, mind „passed”** [T]; és `make fuzz` (ASan+UBSan),
  eredmény **200 000 bemenet, hiba nélkül** [T]. Egy buktató: ebben a környezetben nincs
  `xxd`, ezért a `make` a frissebb `web/index.html` miatt üresre generálta újra a
  `src/web_page.c`-t, és a `test_web` megbukott. A fájlt visszaállítottam
  (`git checkout`), majd `make -o src/web_page.c -o src/icon_data.c test` paranccsal
  futtattam újra, így minden zöld lett. Ez a tesztelés jellemzője, nem kódhiba [T].
- Az `ffsds4` saját tesztjeit (`test.py`) nem futtattam, mert `pycryptodomex` kellene
  hozzájuk, telepíteni pedig nem szabad.

---

## 1. A projektek részletes forráskód-elemzése

### 1.1 `ffsds4` (dogtopus, GPL-3.0-or-later)

**Fájlok** [T]: `start.py` (belépési pont), `ffsds4lib/__init__.py` (gadget és FunctionFS-funkció),
`ffsds4lib/ds4.py` (DS4-adatmodell, hitelesítés, állapotkövetés), `ffsds4lib/console.py`
(interaktív `cmd.Cmd` konzol), `ffsds4lib/sequencer.py` (időzített gombnyomás- és
kar-animáció a konzolhoz), `ffsds4lib/descriptors/ds43p.desc.bin` (160 bájtos HID
reportdescriptor), `test.py` (unittest, beégetett **tesztkulccsal**), `pyproject.toml`,
`Pipfile*`, `poetry.lock`.

**Függőségek** [T] (`pyproject.toml`): `functionfs ^0.9.2`, `pycryptodomex ^3.21.0`, `sty`, `yappi`,
valamint `python = ">=3.11,<3.13"`. A Debian Trixie Python 3.13-at ad. A hídprojekt
ezt úgy kerüli meg, hogy az `ffsds4`-et nem csomagként telepíti, hanem `PYTHONPATH`-ról
tölti be (`installer.py:419-441`, `Environment=PYTHONPATH=...`), és a README szerint
Debian 13 + Python 3.13 alatt tesztelte (`README.md:135-137`) [T]. A `README` a `libaio`
csomagot is előírja a `python-functionfs` miatt [T].

**USB-identitás és -descriptorok** [T]:

- `__init__.py:198-227`: egyetlen konfiguráció egyetlen FunctionFS-funkcióval,
  `idVendor=0x1d6b`, `idProduct=0x0104` (Linux Foundation „Multifunction Composite
  Gadget”), `MaxPower=500`. Ez **nem Sony VID/PID**: harmadik féltől származó,
  licencelt kontrollert emulál (a 0x03-as feature report `hid_usage=0x2721`,
  `ds4.py:363-366`).
- `__init__.py:102-110`: `HIDFunction`, 64/64 bájtos IN/OUT, full-speed intervallum 4 ms
  (`turbo` esetén 1), high-speed `bInterval=6`.
- A `ds43p.desc.bin` reportjai (a bájtokat dekódoltam): input `0x01` (63 bájt adat);
  output `0x05` (31 bájt); feature `0x03` (47 bájt, usage 0x2721); a vendor page
  `0xFFF0` alatt a feature `0xF0` (63), `0xF1` (63), `0xF2` (15), `0xF3` (7).
  **Nincs** benne `0x02`, `0x12` vagy `0xA3` feature report, pedig ezek a hídprojekt
  `legacy` módjában szerepelnek.

**Bemeneti report** [T] (`ds4.py:176-220`, 64 bájt): `type`, 4 kartengely, 3 gombbájt
(az alsó 4 bit a D-pad, a felső 6 bit a reportszámláló, `inc_report_index` +4,
`ds4.py:222-226`), 2 ravasz, szenzor-időbélyeg, akku, gyro[3], accel[3], `state_ext=0x08`,
touchpad-keretszám és 3 touch-keret (`TouchFrame`: seq + 2×32 bit, az aktív bit 7 inverz,
12 bites x és y, `ds4.py:97-174`). A gombok sorrendje `ButtonType` (`ds4.py:43-57`), a
D-pad 0–7, a semleges 8 (`ds4.py:60-69`).

**Visszirányú (feedback) report** [T] (`ds4.py:265-287`, 32 bájt): `type=0x05`, `flags`, 2
bájt kitöltés, `rumble_right` a [4]-en, `rumble_left` az [5]-ön, LED RGB a [6..8]-on,
villogás be/ki a [9..10]-en. **Nincs benne adaptív ravasz vagy haptika.**

**Feature konfiguráció** [T] (`ds4.py:310-422`): a `ControllerFeature` bitjei (motion,
LED, rumble, touchpad); `controller_type` (0 = fő kontroller, 1 = gitár, 6 = kormány);
touchpad- és IMU-paraméterek, a kód szerint „mostly educated guesses” (`ds4.py:292`).

#### A hitelesítés pontos folyamata (`ds4.py:425-966`, `__init__.py:153-175`) [T]

1. A host GET_REPORT kérést küld a `0xF3` reportra; a `get_page_size` (`ds4.py:921-925`)
   visszaadja, hogy a kihívás és a válasz oldalmérete 56 bájt. (A hídprojekt `legacy`
   kódja ugyanezt a választ „RESET”-nek nevezi: `legacy/ps4_full_bridge.py:35`. A
   tartalom mindkettőben ugyanaz: `00 38 38 00…`. A korábbi „0xF3 reset” elnevezés tehát
   a GP2040-CE-szóhasználat, a funkciója valójában az oldalméretek lekérdezése.)
2. A host SET_REPORT kéréssel küldi a `0xF0` reportot: 64 bájt, benne `type`, `seq`
   (nonce-azonosító), `page`, `sbz`, 56 bájt adat és CRC32 (`ds4.py:442-458`). Öt oldal
   jön (0–4); az utolsóból csak 32 bájt hasznos, így összesen 256 bájt
   (`AUTH_REQ_SIZE=0x100`, `ds4.py:543`, `941-942`). **A CRC-hibát és a sorrendhibát csak
   logolja, nem utasítja el** (`ds4.py:930-939`).
3. Az utolsó oldal után a státusz `0x01` („dolgozom”) lesz, az aláírás pedig külön
   szálon fut (`ThreadPoolExecutor`, `ds4.py:877`, `943-945`). A host GET_REPORT
   kéréssel kérdezi le a `0xF2` reportot (16 bájt: type, seq, status, CRC32,
   `ds4.py:948-953`). A státusz kezdetben `0x10`, aláírás közben `0x01`, utána `0x00`,
   hibánál `0xff`.
4. Az aláírás RSA-PSS, SHA-256 hash-sel (`ds4.py:582-589`, `pss.new` alapértelmezett
   saltja = a hash hossza, vagyis 32 bájt [V], ami megegyezik a legacy kód
   `rsa_pss_saltlen:32` beállításával, `legacy/ps4_full_bridge.py:113-114` [T]).
5. A host GET_REPORT kéréssel 19 oldalban olvassa ki a `0xF1` reportot. A válasz
   `0x410` = 1040 bájt (`ds4.py:532-544`): aláírás (256 bájt) + aláírt identitás
   (784 bájt: serial 16 + modulus 256 + exponens 256 + a Sony aláírása az identitáson
   256). Ez 19×56 = 1064 bájtnyi helyet foglal, az utolsó 24 bájt kitöltés; ugyanígy
   a legacy kódban: `signed + serial + n + e + sig + bytes(24)`,
   `legacy/ps4_full_bridge.py:119`. Az utolsó oldal után a tracker visszaáll
   alaphelyzetbe (`ds4.py:961-962`).

**A kulcsblokk szerkezete** [T] (`ds4.py:478-529`, `DS4FullKeyBlock`, 0x590 = 1424 bájt):
`serial[16] | n[256] | e[256] | sig_identity[256] | p[128] | q[128] | dp1[128] | dq1[128] | pq[128]`,
minden egész big-endian. A `DS4Key` ellenőrzi a CRT-tényezők konzisztenciáját
(`ds4.py:554-570`). A fájl sem rövidebb, sem hosszabb nem lehet: csak pontosan ennyi
bájtot olvas be (`ds4.py:550-552`). **Biztonsági megjegyzés:** a `DS4Key` INFO szinten
logolja a nyilvános és a **privát** kulcs SHA-256 ujjlenyomatát (`ds4.py:571-580`). Ez
nem maga a kulcs, de azonosító adat; a hídprojekt `SECURITY.md`-je is a fingerprintek
kitakarását kéri. Saját kódban ezt a logsort el kell nyomni vagy le kell szűrni.

**Mire elég a hitelesítés egy kontroller esetén** (protokoll és adatmodell szintjén):

- A hídprojekt README-je szerint egyetlen, a felhasználó saját kontrolleréből
  jogszerűen származó identitással (serial + nyilvános kulcs + a Sony aláírása) és a
  hozzá tartozó privát kulccsal a PS4 a „szokásos nyolcperces türelmi időn” túl is
  elfogadja az emulált kontrollert (`README.md:25`, `297-310`) [T, amennyiben a README
  igaz; a firmware-verzió nincs megnevezve, ezért 13.52-re nézve [E]].
- A protokollban nincs eszközönkénti nonce-kötés a USB-sorozatszámhoz vagy a
  VID/PID-hez: a válasz csak a nonce aláírása és a statikus identitás [T, a kódból].
  Hogy a PS4 ellenőriz-e ezen felül valamit (például feketelistát vagy azt, hogy
  egyszerre több eszköz használja-e ugyanazt az identitást), az ismeretlen [E].
- Egy identitás egy aláírókulcs. Négy eszköz kiszolgálásához a kód szintjén elég
  lenne ugyanaz a kulcsblokk négyszer betöltve [V]. **Hogy a PS4 elfogad-e négy
  egyidejű eszközt azonos serial/identitással, nem tudjuk** [E]; lásd a 8. fejezetet.

#### Szálkezelés és életciklus (`ffsds4` + `python-functionfs`) [T]

- A `GadgetSubprocessManager` ConfigFS-ben létrehozza a gadgetet, és alapból
  véletlen névvel (`g_…`, `functionfs/gadget.py:282`) csatolja fel a FunctionFS-t. A
  funkciót **külön folyamatban** futtatja (`fork`), és ott opcionálisan `setgid`/`setuid`
  hívást végez a `--uid`/`--gid`/`--username` alapján (`gadget.py:487-519`, `874-878`).
  **Ezzel a root a szülőfolyamatra (ConfigFS, mount, UDC) korlátozható.** A gyermek
  `getFunction()` hívása már a csökkentett jogokkal fut, ezért a kulcsfájlnak olvashatónak
  kell lennie annak a felhasználónak [T, `gadget.py:874-881`]. Az `ffsds4` README-je ezt
  a módot ajánlja (`--username=$USER`); a hídprojekt nem használja.
- UDC-választás: ha nincs `--udc`, pontosan egy UDC-nek kell léteznie, különben hibát
  dob (`gadget.py:149-165`) [T].
- Ha bármelyik funkció-alfolyamat kilép, a szülő a `SIGCHLD` kezelőben
  `KeyboardInterrupt`-ot dob, és **az egész gadget leáll** (`gadget.py:543-561`) [T].
  Összetett (composite) eszköznél így egy pad hibája a másik hármat is ledöntené.
- A funkción belül: az IN végpont `onComplete` visszahívása mindig a következő puffert
  adja vissza (`__init__.py:60-69`), így a report a host poll-ütemében megy ki. A
  `DS4StateTracker` két puffert tart, `RLock` alatt cseréli és szinkronizálja őket,
  majd lépteti a számlálót (`ds4.py:1047-1077`). A hitelesítés aláírása külön szálon
  fut, és a `Console` meg a `Sequencer` is saját szálakat indít (`__init__.py:126-131`,
  `sequencer.py:408-421`).
- A `process_feedback` csak eltárolja az utolsó 0x05 reportot (`ds4.py:1079-1083`), és
  nincs visszahívása; ezért a hídprojekt saját OUT-végpontosztályt használ.

#### Mi köti egy pad-példányhoz, és bővíthető-e?

| Kötés | Hol | Bővíthetőség |
|---|---|---|
| Egy `DS4Function` = egy `DS4Key` + egy `DS4StateTracker` + egy `Console` szál | `__init__.py:95-131` | Több példány is létrehozható, az osztályokban nincs globális állapot [V] |
| `console.Console` cseréje modulszinten, a hídprojektben (`console.Console = HeadlessConsole`) | `ffsds4_dualsense_bridge.py:52` | Globális, de ártalmatlan [T] |
| Modulszintű `logger` felülírása a `DS4Function.__init__`-ben | `__init__.py:111-112` | Kozmetikai [T] |
| Egy gadget = egy UDC; automatikus választáskor pontosan egy UDC kell | `gadget.py:149-165` | Több gadgethez több UDC kell. **Az A20-nak egy OTG-vezérlője van** (5. fejezet) |
| Egy gadgeten belül több `ConfigFunctionFFSSubprocess` is lehet (`usb0`, `usb1`…) | `gadget.py:301-355` | Linux-oldalon összetett eszköz is felépíthető [V]; a PS4 elfogadása [E] |
| Bármelyik funkció kilépése az egész gadgetet leállítja | `gadget.py:543-561` | Hibaizolációhoz saját gadgetkezelő kell (1–4. fázis) |
| A GET/SET_REPORT feldolgozás figyelmen kívül hagyja a `wIndex`-et (az interfészszámot) | `__init__.py:153-175` | Összetett eszköznél ez nem baj, mert minden funkció külön ep0-t (FunctionFS-fájlt) kap [V] |

**Licenc és szerzői jog** [T]: GPL-3.0-or-later (`LICENSE.md`, SPDX-fejlécek). Copyright
(C) 2021- dogtopus. Az `__init__.py` a python-functionfs HID-példáján alapul (Copyright (C)
2018-2020 Vincent Pelletier), a `python-functionfs` maga is GPLv3+.

### 1.2 `rpi-dualsense-ps4-bridge` (GPL-3.0-or-later; a legacy descriptor MIT, GP2040-CE)

**Célplatform** [T]: Raspberry Pi Zero 2 W, Debian 13 64 bit, `dwc2` peripheral módban, Python
3.13, BlueZ, „PlayStation 4 and laptop USB hosts” (`README.md:131-139`). **PS4
firmware-verziót nem nevez meg** [T]; ezért a 13.52 [E].

#### Fájlok szerepe

| Fájl | Szerep |
|---|---|
| `bridge/ffsds4_dualsense_bridge.py` | Elsődleges mód: `ffsds4` + DualSense evdev-adapter, rezgéstovábbítás, input-gate |
| `bridge/make_ds4key.py` | `key.pem` + `serial.txt` + `sig.bin` → 1424 bájtos `ds4key.bin`, atomikus írással, 0600-as joggal |
| `bridge/ps4_feedback.py` | A 0x05 report dekódolása (`DS4Feedback`) |
| `bridge/dualsense_rumble.py` | DS4-motorértékek → evdev `FF_RUMBLE`, 0,5 s-os időtúllépéssel leáll |
| `bridge/dualsense_touch.py` | Type-B multitouch dekóder, 1920×1080 → 1920×942 |
| `bridge/bluetooth_reconnect.py` | `bluetoothctl`-alapú újracsatlakozás, backoff 5→30 s |
| `legacy/ps4_full_bridge.py` | Önálló, `ffsds4` nélküli FunctionFS-implementáció (GP2040-CE-mintára); README szerint „experimental” |
| `legacy/setup_full_gadget.sh`, `cleanup_full_gadget.sh` | Kézi ConfigFS-gadget (054c:09cc, full-speed, „GP2040-CE (PS4)”) |
| `legacy/ps4-mode`, `legacy/ps4-full-bridge.service` | Módváltó és unit a régi telepítéshez |
| `legacy/generate_reference_assets.py`, `legacy/generated/*` | A GP2040-CE PS4-descriptorának (481 B) kimásolása |
| `dashboard/app.py` | Streamlit UI: BT-párosítás, input-gate kapcsoló, teszter, rezgésteszt |
| `dashboard/controller_input.py`, `controller_vibration.py`, `controller_test_server.py` | Élő teszter (8505-ös port, `0.0.0.0`) és kézi rezgés |
| `dashboard/nginx-…conf`, `requirements.txt` | nginx a 80-as porton, `streamlit`, `evdev` |
| `installer.py`, `install.sh` | Telepítő TUI/CLI: apt, venv, ffsds4-pin, `config.txt`, systemd, nginx |
| `examples/systemd/*` | Referencia unitok |
| `tests/*` | 35 egységteszt (telepítő, legacy protokoll, touch, rumble, feedback, BT-backoff, layout) |

#### Függvény- és osztálylista hasznosíthatóság szerint

**Átvehető (kis módosítással):**

| Elem | Hol | Indoklás |
|---|---|---|
| `parse_ds4_feedback`, `DS4Feedback` | `ps4_feedback.py:8-44` | Tiszta függvény, tesztelt; a DS4 Protocol Engine része lesz [T] |
| `TypeBTouchDecoder`, `dualsense_to_ds4_touch` | `dualsense_touch.py:16-66` | Eszközfüggetlen MT-dekóder; a skálázást paraméterezni kell [T] |
| `byte_to_magnitude`, `DualSenseRumbleOutput`, `PS4RumbleForwarder` | `dualsense_rumble.py:26-175` | Általános evdev `FF_RUMBLE`-kimenet, 0,5 s-os watchdoggal leáll; útvonal-szolgáltatóval minden FF-képes padra jó [T] |
| `ReconnectBackoff` | `bluetooth_reconnect.py:49-65` | Tiszta állapotgép [T] |
| `make_ds4key.build`, `atomic_write` | `make_ds4key.py:25-79` | Helyes formátum, nem ír ki kulcsanyagot; a `serial.txt` 16 hex karakteres GP2040-CE-formátumot vár, és 32 hex karakterre balról kitöltve dekódolja (`:35-43`) [T] |
| `HeadlessConsole` minta | `ffsds4_dualsense_bridge.py:42-52` | Az `ffsds4` interaktív konzoljának kikapcsolása [T] |
| `LoggingHIDOUTEndpoint`, `DualSenseDS4Function.getEndpointClass` minta | `:298-333` | A 0x05 reportot még az `ffsds4` előtt elkapja, és kivételt sem enged ki [T] |
| `validate_credentials` | `installer.py:293-327` | Fájlméret- és formátumellenőrzés tartalom kiírása nélkül [T] |

**Átírandó:**

| Elem | Hol | Probléma |
|---|---|---|
| `controller_paths()` | `:55-74` | Fix „DualSense Wireless Controller” névkeresés `/proc/bus/input/devices`-ből; az első találatot veszi; egyetlen eszköz [T]. Helyette udev/sysfs-alapú, VID/PID-es és `uniq`-alapú (BT-cím) eszközazonosítás kell |
| `BUTTONS`, `DualSenseReader.axes` | `:85-100`, `:119` | Hardkódolt evdev-kódok (304–330, ABS 0–5, 16, 17) [T]; ide a Controller Mapper kerül |
| `DualSenseReader` | `:116-295` | Egy eszköz, három démonszál, `commit()` közvetlenül az ffsds4-trackerbe ír. Csak `OSError`-t kap el (`:265`), így más kivétel a szálat csendben megöli, és az utolsó állapot beragadhat [V]. Semleges állapot csak útvonalvesztéskor és `OSError` esetén áll be (`:246-247`, `:267`) [T] |
| `watch_input_gate` | `:138-156` | 0,1 s-os fájlpollozás; a `/run` könyvtárat a systemd hozza létre. Az input-gate ötlete hasznos (Diagnostics/admin), a megvalósítás nem |
| `create_gadget` | `:368-392` | Egyetlen funkció, fix identitás, nincs `--username`; root [T] |
| `bridge_unit()` | `installer.py:419-441` | `User=` nincs, ezért **rootként fut**; `Group=ps4bridge` és `SupplementaryGroups=input` van [T] |
| `controller_input.py` | `dashboard/controller_input.py:23-55` | Ugyanaz a névkeresés; a komment „64-bit Raspberry Pi OS”-t említ (`:20`). A `struct "@llHHi"` natív méretű, így armhf-en (32 bites `long`) 16 bájt, ami megegyezik a 32 bites kernel `input_event` ABI-jával [V]; ezt a Banana Pro-n mérni kell [E] |

**Nem átvehető:**

| Elem | Indoklás |
|---|---|
| `installer.py`: `configure_boot_text`, `detect_boot_config`, platform-ellenőrzés | Pi-specifikus: `/boot/firmware/config.txt`, `otg_mode=1`, `dtoverlay=dwc2,dr_mode=peripheral`, „Raspberry Pi Zero 2 W”-kényszer, `aarch64` (`installer.py:330-371`, `409-414`) [T]. A Banana Pro devicetree-alapú, és armhf |
| `raspberry-pi-usb-ecm-gadget` kezelése | Pi OS-specifikus [T] |
| `dashboard/*` (Streamlit, nginx) | A követelmény szerint az admin felület csak a 6. fázisban jön, és nem lehet az adatútban. A Streamlit A20-on valószínűleg túl nehéz [V]. A teszter hitelesítés nélkül, `0.0.0.0:8505`-ön fut (`controller_test_server.py:76`) [T] |
| `legacy/ps4_full_bridge.py` futtatható formában | `openssl` alfolyamat minden aláírásnál, egyszálú `select`, hardkódolt útvonalak. Viszont **olvasható referencia** a 0x02/0x03/0x12/0xA3 feature-tartalmakhoz és a FunctionFS v2 descriptor-blobhoz (`:29-35`, `:52-62`) [T] |

**Hibakezelés és semleges állapot** [T]: kontroller nélkül az USB-oldal tovább
küldi a semleges reportokat (`README.md:16-17`; `neutralize()`, `:158-161`), és BT-vesztéskor
is semlegesít. A touchpad szála külön engedi el az érintéseket (`:270-295`). A rezgés
0,5 s után magától leáll, ha nem jön új 0x05 (`dualsense_rumble.py:19`, `:153-154`). A
lightbar csak a logba kerül (`:345-365`), a kontrollerre nem.

**Pi-specifikus hardverigény** [T]: `dwc2` peripheral mód és a Pi boot-konfigurációja. A
logika többi része (FunctionFS, ConfigFS, evdev, BlueZ) általános Linux.

### 1.3 AnyPad-PS4 (GPL-3.0-or-later)

Ez egy jailbreakelt PS4-en futó payload. A konzol a különféle kontrollereket virtuális
DualShock 4-ként látja (`README.md:121-131`). „Tested on a PS4 with firmware 13.52”
(`README.md:125`, `COMPATIBILITY.md:3`) [T]; ez a teszt **jailbreakelt** konzolon, eltérő
architektúrával készült.

#### `src/` fájlonként

| Fájl | Szerep | Linux userspace-be portolható? |
|---|---|---|
| `pad.h` | `pad_state` (gombmaszk a `ScePadData` bitkiosztásában, karok 0..255, L2/R2, gyro/accel, 2 érintés DS4-egységekben 1920×942-ig, akku) és `pad_output` (motorok, RGB, játékosszám); `MAX_PADS 4` | **Igen**, ez a belső modell alapja [T] |
| `profiles.h/.c` | Profiltábla és parserek, kimeneti és ébresztő buildek | **Igen**, tiszta C, platformfüggetlen (a `log`/`util`/`crc32` kivételével) [T] |
| `generic.c` | HID-reportdescriptor-parser + alapértelmezett és beépített leképezés + `.map` fájlok | **Igen**, hidraw-hoz [T] |
| `usb_pad.c/.h` | USB-eszközkezelés `libSceUsbd`-n át (a libusb PS4-es megfelelője), interfészválasztás, ébresztés, X360/GIP-parser, olvasószál padonként | **A logika igen**, libusb-re vagy hidraw-ra portolva; az API-hívások nem [T] |
| `ps4_vpad.c/.h` | Kernel-jogosultságemelés (`kernel_set_ucred_authid`, `…_caps`, `ps4_vpad.c:325-358`, authid `0x3800000000010003`), `scePadVirtualDeviceAddDevice/InsertData/DeleteDevice` (`:446`, `:595`), eszközazonosítás a kernel logjából | **Nem**, PS4-specifikus és jailbreaket igényel [T] |
| `netpad.c/.h` | WebSocket-szerver (8096-os port), saját SHA-1/base64, beágyazott HTML/JS a böngésző Gamepad API-jához | **Nem kell**: a követelmény tiltja a hálózati adatutat. A binárisformátum-ötlet viszont hasznos (lásd lent) |
| `web.c/.h`, `web_page.c` (generált, 156 kB), `web/index.html` | Menü a 8095-ös porton | Nem (a 6. fázis saját felülete) |
| `ps4_main.c` | Fő ciklus 4 ms-onként (`usleep(4000)`, `:226`): `web_poll`, `vpad_poll`, `usb_pad_poll`, hálózatfigyelés, leállás | A felépítés minta, a kód nem portolható |
| `ps4_power.c`, `ps4_ui.c`, `ps4_apps.c`, `ps4_sysinfo.c`, `launcher.c`, `icon_data.c` (generált, 372 kB) | PS4-rendszerhívások, ikon, alkalmazásindító | Nem |
| `lock.c`, `log.c`, `util.c`, `crc32.c`, `netinfo.c` | Példányzár, log, idő és bájtsorrend, CRC32 (a BT-s Sony-kimeneti reportokhoz) | `util`, `crc32`, `log`: igen |
| `nosleep_media.h` | NoSleep.js-videók (MIT) | Nem |
| `tools/sce_stubs/*` | Linkelési stubok a PS4 SDK-hoz | Nem |
| `maps/EXAMPLE.map` | Leképezőfájl-minta | Igen, mint formátum |

#### Profilok, VID/PID, reportformátumok, ébresztés (`profiles.c`) [T]

| Profil | VID:PID | Bemeneti reportok | Kimenet és ébresztés |
|---|---|---|---|
| DualShock 4 (`:92-158`) | 054C:05C4, 054C:09CC, 0F0D:00F6 (Hori Onyx), 1532:1009, 1532:100A (Razer Raiju), 2E95:7725 (SCUF), 0F0D:0123 | 0x01: [1..4] karok, [5..7] gombok, [8] L2, [9] R2. 0x11 (BT): [3..6] karok, [7..9] gombok, [10][11] ravaszok, [15..20] gyro, [21..26] accel, [32] akku, [35] touch-szám, [37..44] 2 pont | 0x11 BT-output CRC32-vel: [6] gyenge, [7] erős motor, [8..10] RGB; ébresztés = egy output report; `wake_feature 0x05` (klónokhoz) |
| DualSense (`:171-234`) | 054C:0CE6, 054C:0DF2 (Edge) | 0x01 rövid: [1..4] karok, [5..8] gombok, [9][10] ravaszok. 0x31 (BT): [2..5] karok, [6][7] ravaszok, [9..12] gombok, [17..22] gyro, [23..28] accel, [34..41] 2 touch-pont, [54] akku | 0x31 output: [4] gyenge, [5] erős, [45] játékos-LED, [46..48] RGB + CRC |
| Xbox One/Series BT (`:255-353`) | 045E:02E0, 02FD, 0B00, 0B05, 0B0A, 0B13, 0B20, 0B21, 0B22 | 0x01: 16 bites karok, 10 bites ravaszok, hat 1..8; 16 bájtos és ≥17 bájtos gombkiosztás; 0x02 Xbox-gomb; 0x04 akku | 0x03: 4 motor (0..100), időtartam és ismétlés |
| Switch Pro (`:355-551`) | 057E:2009, 2017, 2019, 201A, 201E | 0x3F egyszerű; 0x30 teljes: 12 bites karok, IMU; nyugalmi kalibráció 16 mintából | 0x01 subcommand: 0x03 (mód 0x30), 0x40 (IMU), 0x48 (rezgés), 0x30 (játékos-LED) |
| Joy-Con (`:553-638`) | 057E:2006, 2007 | 0x30, oldalra fordítva értelmezve | mint a Switch |
| Wii / Wii U Pro (`:640-794`) | 057E:0306, 0330 | 0x30 core, 0x34 + kiterjesztés; 0x20 → REINIT | 0x11 LED, 0x16 írás (0xA400F0 ← 0x55, 0xA400FB ← 0x00), 0x12 mód 0x34 |
| GameSir (`:796-945`) | 3537:0108, 1004, 1012, 1097, 1014, 1067, 1001, 1009, 1011 | 0x05 (10 bájtos HID), XInput-szerű 0x00, Switch-mód, DS4-mód, általános | nincs |
| DualShock 3 USB (`:947-1016`) | 054C:0268 | 0x01: [2..4] gombok, [6..9] karok, [18][19] nyomás | 36 bájtos output SET_REPORT-tal; ébresztés: GET_REPORT feature 0xF2 |

`usb_pad.c`-ben [T]:

- Interfészosztályok: XInput `ff/5d/01`, GIP `ff/47/d0`, HID `03` (`:1-12`, `:108-140`).
- GIP bekapcsolás: `05 20 <seq> 01 00` (`:271`), a Guide-gomb nyugtázása (`:330`).
- X360 LED: `01 03 <0x06+slot>` (`:277`).
- Switch USB-kézfogás: `80 02`, `80 03`, `80 02`, `80 04` (`:209`), utána 500 ms-onként
  0x10-es keep-alive (`:225-237`).
- A DualShock 3 felébresztése GET_REPORT-tal a 0xF2 feature reportra (`:693`).
- Microsoft OS string (0xEE) lekérdezése, hogy a „hostfüggő” padok Xbox módban
  maradjanak (`:663-668`).
- A licencelt padok audio-interfészeinek lefoglalása (`:643-660`).
- **A Sony padokat (054C, kivéve 0268) kihagyja** (`:617`).

**Fontos lelet** [T]: a `build_output` és a `rumble_refresh_ms` mezőt a `profiles.c`-n kívül
**semmi nem hívja** (grep-pel ellenőrizve). Az AnyPad PS4-portja tehát **nem továbbít
rezgést** a fizikai kontrollerre; a kimeneti buildereket csak az ébresztő szekvenciák
használják. A rezgéstovábbítást nálunk újra kell írni (evdev `FF_RUMBLE` vagy hidraw output).

**Lehetséges hiba, csak saját portnál számít** [V]: a `ds5_parse` 0x01-es ágának
offszetei a BT-s „rövid” reportot követik. A DualSense **USB-s** 64 bájtos 0x01-es
reportjában más a kiosztás (a Linux `hid-playstation` szerint a ravaszok a karok után
jönnek, a gombok csak utánuk) [E: a kernelforrással egybe kell vetni]. Az AnyPadban ez
nem jön elő, mert a Sony USB-padokat kihagyja. Nálunk viszont a DualSense/DS4 olvasását
eleve a kernel `hid-playstation` drivere végezze evdev-en át [V].

#### `generic.c` működése [T]

1. `parse_descriptor` (`:111-189`): lépésenként végigmegy a HID-elemeken, 4 mélységű
   push/pop veremmel, és reportazonosítónként bitoffszetet számol (`offset[256]`). A
   Generic Desktop X…Wheel (0x30–0x37) és a Hat (0x39), a Simulation Brake/Accelerator,
   a Button 1–32, valamint a Consumer AC Home/AC Back mezőket ismeri fel; a nem
   konstans inputokat menti. Méret- és határellenőrzéssel elutasítja a hibás
   descriptort (`:168-170`).
2. `default_mapping` (`:209-246`): ≥15 gomb esetén Android/Xbox-sorrend, egyébként
   DirectInput; karok és ravaszok heurisztikával (Z/RZ vagy RX/RY, Brake/Accel).
3. `builtin_map` (`:301-372`): 30 beépített VID/PID-leképezés (GameSir, 8BitDo, iPega,
   SteelSeries, Shield, MOGA stb.).
4. `load_map` (`:374-394`): `<map_dir>/VVVV_PPPP.map`, `buttonN = <vezérlő>`,
   `<szerep> = <tengely>`, `invert <szerep>`.
5. `generic_parse` (`:453-518`): reportazonosítónként csak azokat a vezérlőket frissíti,
   amelyeket az adott report tartalmaz (maszkolva), a tengelyeket pedig 0..255-re
   skálázza.

Ez Linuxon hidraw-val közvetlenül használható [V]. A `.map` formátum jó kiindulópont a
„konfigurálható leképezéshez”.

#### A netpad protokoll [T] (csak dokumentációs céllal; a hídban nem használjuk)

HTTP GET `/` → HTML/JS; `GET /ws?n=<név>` → WebSocket. A kliens bináris keretet küld:
`u32 LE gombmaszk`, 4 bájt kar, 2 bájt ravasz (10 bájt), opcionálisan + 1 bájt
ujj-flagek + 2×(id, x u16, y u16) (21 bájt) (`netpad.c:197-214`, `:424-476`). Legfeljebb 8
kliens (`:307`), helyi IP-szűréssel (`:526-532`), jelszó nélkül. A tömör, rögzített méretű
állapotkeret ötlete átvehető az MCU-s Sink UART-protokolljához (7. fejezet).

#### A tesztek [T]

`tests/test_profiles.c` (parserek szintetikus reportokkal), `test_vpad.c` (`ps4_vpad.c` PS4-API
helyettesítőkkel), `test_web.c`, `test_netpad.c`, `test_lock.c`, `test_launcher.c` és `test_fuzz.c`
(véletlen bemenet minden parserre). **Amit bizonyítanak:** a parserek a kódolt
offszetekre helyes `pad_state`-et adnak, és hibás bemenetre nem fagynak le. **Amit nem
bizonyítanak:** azt, hogy a valódi kontrollerek ténylegesen ilyen reportokat küldenek;
azt, hogy a PS4 elfogadja az eredményt; és semmit USB-időzítésről, ébresztésről vagy
újracsatlakozásról.

---

## 2. Felhasználható fájlok és függvények listája

| # | Forrás | Elem | Cél modul | Mód |
|---|---|---|---|---|
| 1 | ffsds4 `ds4.py` | `InputReport`, `TouchFrame`, `FeedbackReport`, `FeatureConfiguration`, `ButtonType`, `DPadPosition` | DS4 Protocol Engine | Közvetlen használat (függőségként) vagy port |
| 2 | ffsds4 `ds4.py` | `DS4Key`, `DS4AuthStateTracker` | DS4 Protocol Engine / AuthProvider | Függőségként; a fingerprint-logot el kell nyomni |
| 3 | ffsds4 `ds4.py` | `DS4StateTracker`, `DS4TouchStateTracker` | USB Gadget Manager (FunctionFS-Sink) | Függőségként |
| 4 | ffsds4 `__init__.py` | `DS4Function`, `HIDINEndpoint`, `HIDOUTEndpoint` | FunctionFS-Sink | Leszármaztatás (mint a hídban) |
| 5 | python-functionfs `gadget.py` | `Gadget`, `ConfigFunctionFFSSubprocess`, `--username` | USB Gadget Manager | Függőség; a hibaizoláció miatt saját burkoló kell |
| 6 | híd `ps4_feedback.py` | `parse_ds4_feedback` | DS4 Protocol Engine | Átvétel |
| 7 | híd `dualsense_touch.py` | `TypeBTouchDecoder` | Input Manager (evdev-touch) | Átvétel, paraméterezve |
| 8 | híd `dualsense_rumble.py` | `DualSenseRumbleOutput`, `PS4RumbleForwarder` | Input Manager (feedback) | Átvétel, általánosítva („EvdevRumbleOutput”) |
| 9 | híd `bluetooth_reconnect.py` | `ReconnectBackoff`, `reconnect_paired_dualsense` | Device Manager | A backoff átvehető; a `bluetoothctl` kiváltása D-Bus-szal [V] |
| 10 | híd `make_ds4key.py` | `build`, `atomic_write` | Eszköz (tools) | Átvétel |
| 11 | híd `ffsds4_dualsense_bridge.py` | `HeadlessConsole`, `LoggingHIDOUTEndpoint` minta | FunctionFS-Sink | Átvétel |
| 12 | híd `legacy/ps4_full_bridge.py` | `CALIBRATION`, `DEFINITION`, `MAC`, `VERSION`, `descriptor_blob` | Referencia az [E] tesztekhez | Csak referencia |
| 13 | AnyPad `pad.h` | `pad_state`, `pad_output`, gombbitek | Belső modell | Port (C-ben vagy Pythonban) |
| 14 | AnyPad `profiles.c` | `hat_buttons`, `sony_*`, `xbox_parse`, `switch_*`, `joycon_*`, `wii_*`, `gamesir_parse`, `ds3_*`, ébresztők | Input Manager (hidraw-backend) | Port |
| 15 | AnyPad `generic.c` | Az egész fájl | Controller Mapper (általános HID) | Port |
| 16 | AnyPad `usb_pad.c` | `read_ifaces`, `choose_iface`, `hid_wake`, `wake`, `parse_x360`, `parse_gip`, a Switch-kézfogás és a keep-alive | Input Manager (libusb-backend) | Logikai port |
| 17 | AnyPad `crc32.c`, `util.h` | CRC32, LE-olvasás | Közös | Port |
| 18 | AnyPad `tests/test_profiles.c`, `test_fuzz.c` | Tesztvektorok | Tesztek | Átvétel |

## 3. Átvehető algoritmusok és megoldások

1. **DS4-hitelesítési állapotgép** (`ffsds4` `DS4AuthStateTracker`): oldalazott kihívás és
   válasz, aszinkron aláírás, státuszpollozás [T].
2. **Duplapufferes reportküldés** a host poll-ütemében (`prepare_for_report_submission`) [T].
3. **Touch-keret sorbaállítás**: legfeljebb 3 keret reportonként; „sustain”, vagyis a
   nyomva tartott érintés ismétlése; érintés-ID-léptetés 7 biten (`ds4.py:606-679`) [T].
4. **Semleges állapot** minden forrásvesztésnél, mialatt az USB és a hitelesítés tovább
   fut (híd) [T].
5. **Rezgés-watchdog**: a motorok leállnak, ha 0,5 s-ig nem jön feedback (híd) [T].
   Hogy a PS4 milyen gyakran küld 0x05-öt, mérni kell [E].
6. **Exponenciális BT-újracsatlakozás**, csak bondolt eszközzel (híd) [T].
7. **HID-descriptor-alapú általános leképezés** + `.map` felülírás (AnyPad `generic.c`) [T].
8. **Eszközfüggő ébresztő szekvenciák** (Switch-kézfogás és keep-alive, GIP power-on, DS3
   feature, Wii-kiterjesztés) [T]. Linuxon a kernel driverek egy részük helyett is
   elvégzik ezt (`hid-nintendo`, `xpad`, `hid-sony`) [V].
9. **Kalibráció induláskor** (Switch, nyugalmi offszet) [T].
10. **„Csak az első valós report után kérj slotot”** (AnyPad `usb_pad.c:16-18`, `handle`), hogy
    a néma pad ne foglaljon játékoshelyet [T].
11. **Rögzített méretű bináris állapotkeret** (AnyPad netpad) az MCU-s Sink protokolljához [V].

## 4. A két projekt közötti technikai különbségek

| Szempont | rpi-dualsense-ps4-bridge | AnyPad-PS4 |
|---|---|---|
| Hol fut | Külső Linux SBC (Pi Zero 2 W) | Magán a PS4-en, payloadként |
| Mit lát a PS4 | Valódi USB-eszközt (FunctionFS), hitelesítéssel | Szoftveres virtuális padot (`scePadVirtualDevice*`), hitelesítés nélkül |
| Feltétel | Jogszerűen beszerzett hitelesítési identitás; nincs jailbreak | Jailbreak, GoldHEN vagy payload-loader, kernel-jogosultság |
| Padok száma | 1 (egy gadget, egy DualSense) | 4 (a payload korlátja: `MAX_PADS`) |
| Bemenetek | Bluetooth DualSense evdev-en | USB (X360, GIP, HID-profilok, általános HID), hálózat (böngésző) |
| Sony-padok | DualSense (BT) a cél | A Sony USB-padokat a konzol kapja, kihagyja őket |
| Rezgés vissza | Igen (0x05 → `FF_RUMBLE`) | **Nem** (a `build_output` nincs bekötve) |
| Lightbar | Csak logolja | Nem |
| Touchpad | Igen (DualSense → DS4) | Igen (DS4/DS5 BT-reportból, netpadból) |
| Nyelv | Python 3.13 | C11 |
| Belső modell | Nincs: evdev-kódok mennek közvetlenül a DS4-reportba | Van: `pad_state`/`pad_output` |
| Leképezés | Hardkódolt | Profilok + általános HID + `.map` |
| Jogosultság | Root (systemd unit `User=` nélkül) | PS4-kernelcred-emelés |
| Tesztek | 35 unittest | 6 C-tesztprogram + fuzz |

A követelményeket egyik projekt sem fedi le egyedül. A **kimeneti oldal** a hídprojektből
és az `ffsds4`-ből jön, a **bemeneti oldal és a belső modell** ötletei az AnyPadból.

## 5. A Banana Pro hardveres korlátai

| # | Állítás | Jelölés és forrás |
|---|---|---|
| 1 | Az A20 SoC-nak egy OTG (musb) vezérlője van a 0x01c13000 címen, `compatible = "allwinner,sun4i-a10-musb"`, `dr_mode = "otg"`, alapértelmezésben `status = "disabled"` | [T] `sun7i-a20.dtsi:592-604` (mainline) |
| 2 | **A mainline `sun7i-a20-bananapro.dts` nem engedélyezi a `usb_otg` csomópontot** (a fájlban nincs `&usb_otg`), és a `&usbphy` alatt nincs `usb0_id_det-gpios`, `usb0_vbus_det-gpios` vagy `usb0_vbus-supply`, csak `usb1/usb2_vbus-supply` | [T] `sun7i-a20-bananapro.dts:215-219`, keresés: 0 találat a `usb_otg`-ra |
| 3 | Ezért mainline kernelen a Banana Pro OTG-portja **alapból nem működik gadgetként**; devicetree-overlay vagy patch kell, amely a `usb_otg`-ot `okay`-re állítja (és opcionálisan `dr_mode = "peripheral"`-t ad meg) | [V] a 2. pontból; az Armbian-image tényleges DT-je [E] (a script ezt kiolvassa) |
| 4 | A musb sunxi glue **mindhárom módot támogatja**: HOST, PERIPHERAL és OTG, a `CONFIG_USB_MUSB_HOST/GADGET/DUAL_ROLE` beállítástól függően | [T] `drivers/usb/musb/sunxi.c:696-718` (mainline). **Ez ellentmond a korábbi „peripheral-only módot nem támogat” állításnak**; az lehet, hogy régebbi kernelre volt igaz [E] |
| 5 | OTG módban, ID-detektáló GPIO nélkül a PHY **peripheral módra esik vissza**, VBUS-detektálás nélkül pedig a VBUS-t „magasnak” veszi | [T] `drivers/phy/allwinner/phy-sun4i-usb.c:402-435` |
| 6 | Az A10/A20 musb konfigurációja: ep0 + 5 végpontszám (ep1–ep5), mindegyiken külön TX és RX FIFO, 512 bájttal | [T] `sunxi.c:632-664`, `814-817` |
| 7 | Egy DS4-funkcióhoz 1 interrupt IN + 1 interrupt OUT végpont kell (ep0-n felül) | [T] `ffsds4` `HIDFunction`, és a legacy descriptor: `ps4_full_bridge.py:54-59` |
| 8 | Ebből: 1 DS4-gadget bőven belefér; 4 DS4-funkcióból álló összetett eszköz (4 IN + 4 OUT) **végpontszámban** belefér az 5-be | [V] (6+7). A FIFO-RAM elég-e, és a musb dinamikus FIFO-kiosztása jól működik-e 4 funkcióval, [E] |
| 9 | Egy UDC-hez egyszerre egy gadget köthető, ezért egy Banana Pro önmagában **egy** USB-eszközként jelenik meg a PS4 felé | [T] `gadget.py:149-165`, `:357-362` (UDC-hozzárendelés); [V] egy UDC = egy eszköz |
| 10 | Az Armbian a táblát „Banana Pi Pro” néven kezeli (`BOOTCONFIG="Bananapro_defconfig"`), kernelágak: `current, edge, legacy`, `BOARD_MAINTAINER=""` (nincs karbantartó, community-támogatás) | [T] `armbian/build` `config/boards/bananapipro.csc`; hogy ez pontosan a LeMaker Banana Pro-t jelenti-e, [E] (a `Bananapro_defconfig` és a mainline DTS-név erre utal [V]) |
| 11 | Overlay-előtag: `sun7i-a20` | [T] `config/sources/families/sun7i.conf` |
| 12 | Az OTG-port nem ad 5 V-ot host módban (Armbian-fórum) | [E] (nem értem el). **Peripheral módban nem is kell 5 V-ot adnia**, a PS4 adja a VBUS-t [V]. **Új kockázat:** ha a Banana Pro OTG VBUS-a össze van kötve a tábla 5 V-os sínjével, a PS4 és a Banana Pro tápja egymásba táplálhat [E]; a kapcsolási rajzot ellenőrizni kell |
| 13 | CPU: 2× Cortex-A7, ~1 GHz (Armbian `CPUMAX=1010000`, `sun7i.conf`), 1 GB RAM, armhf (32 bites) | [T] az Armbian CPU-frekvenciára; az armhf [V] |
| 14 | AP6210 BT: BCM20710-alapú, UART-HCI, firmware-függő | [E]; a BT-kapcsolatok egyidejű száma és a késleltetés 4 paddal [E] |
| 15 | Host portok: a DTS `ehci0/1` és `ohci0/1` vezérlőket engedélyez, vagyis két host-vezérlőt | [T] `sun7i-a20-bananapro.dts:101-107`, `:171-177`; a fizikai portok száma (2 USB-A + OTG) [E] |

**Összegzés** [V]: a Banana Pro **egy natív DS4-gadgetre** alkalmas, ha a DT engedélyezi az
OTG-t, és a kernel `CONFIG_USB_MUSB_GADGET` vagy `DUAL_ROLE`, `CONFIG_USB_CONFIGFS`,
`CONFIG_USB_F_FS` és `CONFIG_USB_LIBCOMPOSITE` beállítással fordult. Négy **külön** USB-eszköz
egyetlen OTG-vezérlővel nem lehetséges.

## 6. Az USB Gadget mód megvalósíthatósága

Szükséges láncszemek és állapotuk:

| Láncszem | Állapot | Ellenőrzés |
|---|---|---|
| `usb_otg` engedélyezve a DT-ben (`status=okay`), `dr_mode` `peripheral` vagy `otg` | Mainline-on nincs engedélyezve [T]; Armbianon [E] | Script: `/proc/device-tree/.../usb@1c13000/{status,dr_mode}` |
| `CONFIG_USB_MUSB_SUNXI`, `CONFIG_USB_MUSB_GADGET` vagy `DUAL_ROLE` | [E] | Script: kernel-konfig |
| `CONFIG_PHY_SUN4I_USB` | [E] | Script |
| `CONFIG_USB_LIBCOMPOSITE`, `CONFIG_USB_CONFIGFS`, `CONFIG_USB_F_FS`, `CONFIG_USB_CONFIGFS_F_FS` | [E] | Script |
| `/sys/class/udc/` alatt egy bejegyzés (pl. `musb-hdrc.1.auto`) | [E] | Script |
| `configfs` és `functionfs` a `/proc/filesystems`-ben | [E] | Script |
| `libaio` (python-functionfs) | Trixie-n `libaio1t64` [T: a hídprojekt telepítője] | Script |
| Python 3.13 + functionfs 0.9.2 armhf-en | A hídprojekt aarch64-en tesztelte [T]; armhf-en [E] | 1. fázis |
| Tápellátás és VBUS-backfeed | [E] | Kapcsolási rajz, multiméter |
| PS4 13.52 felismeri, hitelesíti, 10 percen túl is működik | [E] | **Csak hardveren** |

Ha a DT-overlay szükséges, az 1. fázis első lépése egy minimális, saját overlay
(`usb_otg { status = "okay"; dr_mode = "peripheral"; }`) lesz, az Armbian
`armbianEnv.txt` `user_overlays` mechanizmusával [V]. Hogy pontosan hogyan, az az Armbian-image
ismeretében dől el [E].

## 7. Négy külön PS4-kontroller emulálásának realitása

**A közös alap mindegyik architektúrában:** az Input Manager, a Controller Mapper, a Device
Manager és a DS4 Protocol Engine azonos. Csak a **Sink** (kimeneti adapter) cserélődik.

### 7.1 A Sink absztrakció (terv, nem kód)

```
DS4Frame  = a DS4 Protocol Engine kimenete: 64 bájtos 0x01 input report (a számláló nélkül)
DS4Feedback = a PS4-től kapott 0x05 (motorok, RGB, villogás) + időbélyeg

interface Sink:
    slots() -> int                       # hány PS4-játékost tud kiszolgálni
    open(slot) / close(slot)
    submit(slot, DS4Frame)               # nem blokkol; mindig a legutóbbi állapot megy ki
    on_feedback(slot, callback(DS4Feedback))
    status(slot) -> {enumerated, authenticated?, last_poll, errors}

interface AuthProvider:                  # csak a natív hitelesítő Sinkeknek
    page_size(), set_challenge(page), status(), response(page)
```

Implementációk: `NullSink` és `RecordingSink` (tesztekhez), `FunctionFSSink` (ffsds4, egy slot),
`CompositeFunctionFSSink` (kísérleti, 4 slot), `McuUartSink` (N darab MCU, slotonként egy
eszköz), később `RemoteSbcSink`. A Device Manager csak a `Sink` interfészt látja, így a natív
gadget és az MCU-s megoldás a bemeneti oldal változtatása nélkül váltható.

### 7.2 Architektúrák

| | A) Összetett eszköz (1 gadget, 4 HID-interfész) | B) Több gadget / több SBC | C) Külső MCU-k (4 USB-eszköz) | D) Hibrid / egyéb |
|---|---|---|---|---|
| Leírás | Egy USB-eszköz, 4 DS4 FunctionFS-funkcióval | Egy UDC-n nem megy (5.9); helyette 4 gadget-képes SBC (pl. Pi Zero 2 W), a Banana Pro vezérli őket | 4 natív USB-eszközképes MCU (pl. RP2040), a Banana Pro UART/SPI-n küldi nekik a DS4Frame-et; USB-hub a PS4 előtt | D1: 1 natív gadget a Banana Pro-n + 3 MCU. D2: Bluetooth-os DS4-emuláció a PS4 felé. D3: egy pad, multiplexelve |
| Linux-oldal | Végpontszámban belefér [V]; FunctionFS + python-functionfs támogatja [T] | Natív, bevált út (a hídprojekt) [T] | A Banana Pro csak sorosan küld adatot [V] | D1: A + C kombinációja |
| PS4-oldal | **Ismeretlen** [E]. Valószínűtlen [V], mert a PS4 USB-s DS4-kezelése eszközszintű; nincs rá forrásunk | Minden SBC külön eszköz, ahogy a hídprojektben [V]; hub [E] | Minden MCU külön eszköz [V]; hub [E] | D2: a PS4 BT-párosítása USB-s link key-csere után történik, egy BT-adapter egy BD_ADDR, és az AP6210 a bemeneti padokkal is foglalt [V], ezért nem javasolt. D3: nem teljesíti a 4 külön játékost |
| Hitelesítés | 4 funkció, közös vagy külön identitás [E] | SBC-nként saját aláíró | MCU-nként: (a) helyi RSA az MCU-n (a GP2040-CE RP2040-en így működik [V/E]), vagy (b) a Banana Pro AuthProvidere aláír, és a 0xF0–0xF3 kéréseket UART-on továbbítja (a PS4 pollozza a státuszt, így van idő) [V] | – |
| Hibaizoláció | Gyenge: az összes funkció egy gadgetben él, és a python-functionfs egy funkció kilépésekor mindet leállítja [T] | Jó | Jó: MCU-nként | – |
| Költség és bonyolultság | Csak szoftver, a legolcsóbb kísérlet | 4 SBC: drága, sok táp | 4 olcsó MCU + hub + kábelezés; MCU-firmware kell | – |
| Késleltetés | Alacsony | Hálózat/UART + SBC | UART 1–2 Mbit/s mellett ~1 ms alatt egy 64 bájtos keret [V] | – |
| Kockázat | A PS4 elutasíthatja | Tápellátás és hub | MCU-firmware (külön projekt), hub | – |

### 7.3 Javaslat

1. **1. fázis:** egy natív `FunctionFSSink` a Banana Pro-n, ami bizonyítja a teljes láncot
   (OTG, gadget, hitelesítés, PS4 13.52).
2. **4. fázis eleje:** az **A)** összetett eszköz kipróbálása olcsó szoftveres kísérletként,
   egyetlen PS4-teszttel (felismer-e 2 vagy 4 játékost). Siker esetén megmarad, de a
   hibaizolációhoz saját gadgetkezelő kell.
3. Ha az A) nem működik: **C)** `McuUartSink`. Elsődlegesen a (b) hitelesítési relé
   ajánlott, hogy kulcsanyag ne kerüljön az MCU-kra; a Banana Pro maradjon az egyetlen
   hely, ahol a kulcs van [V]. Az MCU-firmware külön, később tervezendő részprojekt.
4. A hub-kompatibilitás tesztje a PS4 Slimen (2 USB-port) [E] még a C) előtt.

## 8. Hitelesítési követelmények

**Adatok (pad-identitásonként):** `key.pem` (RSA-2048 privát kulcs), `serial.txt` (16 hex
karakter), `sig.bin` (256 bájt, a Sony aláírása az identitáson). Ezekből áll elő a
`ds4key.bin` (1424 bájt) [T]. A hídprojekt README-je szerint a három fájlnak **ugyanabból a
kontrollerből** kell származnia, és a hibás serial-formátum a nyolcperces lefagyás tipikus
oka (`README.md:297-310`) [T].

**Folyamat:** 1.1 fejezet, 1–5. lépés [T].

**Feltételek:**

- A hitelesítés minden csatlakozáskor, és a README szerint időszakosan is lefut [V/E].
  A PS4 türelmi ideje alatt (~8 perc) a pad hitelesítés nélkül is működik (`README.md:297-310`)
  [T a README-re].
- Az aláírás A20-on: a hídprojekt aarch64-en mért időt sem közöl. Pythonos `pycryptodomex`
  RSA-2048 aláírás Cortex-A7-en várhatóan 0,1 s körüli [V/E]; az aszinkron státuszpollozás
  ezt elviseli [T].

**Per-pad identitás kérdése** [E]:

- A protokoll nem tiltja, hogy több eszköz ugyanazt az identitást használja [T, a kódból].
- Hogy a PS4 13.52 elfogad-e két vagy négy egyidejű eszközt azonos serial-lal, nem tudjuk.
  Csak hardveren, a felhasználó tesztelheti, saját identitásokkal.
- Biztonságos tervezési alapelv: **slotonként konfigurálható identitás** (`slot → ds4key.bin`),
  úgy, hogy egy identitás több slothoz is hozzárendelhető legyen, ha a teszt ezt igazolja.

**Jogi és etikai korlátok:**

- A projekt **nem tartalmaz és nem szerez be** kulcsot. Nem dokumentál kulcskinyerést
  kontrollerből, és nem kerül meg semmilyen biztonsági mechanizmust. Kizárólag a
  felhasználó által jogszerűen birtokolt adatokkal dolgozunk.
- A kulcsfájlok soha nem kerülhetnek a repóba, logba vagy kimenetbe (`.gitignore`; az
  `ffsds4` fingerprint-logjának elnyomása; a riportscript kitakar).
- A kulcsfájlt a szolgáltatásfelhasználó olvashatja, 0600-as joggal, a repón kívül
  (`/etc/anypad-bridge/auth/`) [V terv].
- A hitelesítési identitás jogi helyzete (szerződési és ToS-kérdések) országonként eltérhet;
  ezt a felhasználónak kell megítélnie. A projekt jogi tanácsot nem ad.

## 9. Várható problémák és kockázatok

| # | Kockázat | Valószínűség | Hatás | Kezelés |
|---|---|---|---|---|
| R1 | Az Armbian-image DT-je nem engedélyezi az OTG-t | Magas [V] (mainline-on nincs engedélyezve [T]) | Blokkoló | Saját overlay (1. fázis) |
| R2 | A kernel `MUSB_GADGET`, `CONFIGFS` vagy `F_FS` nélkül fordult | Közepes [E] | Blokkoló | Script; szükség esetén saját kernel vagy modul |
| R3 | A PS4 13.52 nem fogadja el az emulált, hitelesített DS4-et | Közepes [E] | Blokkoló | 1. fázis hardverteszt; a firmware a hídprojektnél sincs megnevezve |
| R4 | Az összetett eszközt a PS4 nem kezeli 4 padként | Magas [V] | 4 játékos az A)-val nem megy | C) MCU-k |
| R5 | A PS4 elutasítja a duplikált identitást | Ismeretlen [E] | 4 identitás kellene | Slotonkénti identitás-konfiguráció |
| R6 | VBUS-backfeed a PS4 és a Banana Pro tápja között | Ismeretlen [E] | Hardverkárosodás | Kapcsolási rajz, mérés, szükség esetén VBUS-leválasztás (kábel/dióda) |
| R7 | Python-terhelés A20-on (4 bemeneti és 1–4 kimeneti stream, 250 Hz) | Közepes [E] | Késleltetés, jitter | Mérés az 1. és 2. fázisban; a kritikus út C-ben, ha kell |
| R8 | armhf-specifikus hibák (functionfs, ctypes-struktúrák, `input_event` mérete) | Alacsony–közepes [V] | Hibás reportok | 1. fázis tesztjei armhf-en |
| R9 | AP6210 BT-stabilitás 4 paddal | Közepes [E] | Kieső padok | USB BT-dongle alternatíva |
| R10 | Hub-kompatibilitás a PS4-en | Közepes [E] | C) nem működik | Korai hubteszt |
| R11 | Egy pad hibája ledönti a gadgetet (python-functionfs `SIGCHLD`) | Biztos összetett módban [T] | Mind a 4 pad leáll | Saját gadgetkezelő vagy padonként külön eszköz |
| R12 | Beragadt gomb vagy tengely nem kezelt kivétel után | Közepes [V] (a hídban csak `OSError`-t kap el) | Játékhiba | Watchdog: ha N ms-ig nincs friss állapot, semleges állapot jön; minden kivétel elkapva |
| R13 | A kulcs ujjlenyomata a logba kerül | Biztos, ha az `ffsds4`-et változatlanul használjuk [T] | Adatszivárgás | Logfilter |
| R14 | Root futtatás | Biztos, ha a hídprojektet követjük [T] | Biztonsági | `--username` szerinti jogcsökkentés |
| R15 | Az USB-kapcsolat megszakadása utáni helyreállás | Közepes [E] | Pad eltűnik | `onDisable`/`onEnable` kezelése; tesztelni kell |
| R16 | Lightbar és játékosszám: a PS4 a 0x05-ben a lightbart küldi, a játékosszám ebből csak következtethető | Közepes [V] | Rossz LED a fizikai padon | Színtábla, hardverteszt |
| R17 | Adaptív ravasz és haptika igénye | – | – | **Nem megvalósítható:** a DS4 0x05 reportban nincs ilyen mező [T `ds4.py:265-287`]; a PS4 DS4-protokollon nem küld ilyet [V] |

## 10. Részletes fejlesztési terv (0–6. fázis)

Jelölés: **[PC]** a fejlesztői gépen vagy CI-ben ellenőrizhető; **[HW]** csak a felhasználó
tudja ellenőrizni Banana Pro-n vagy PS4-en.

### 0. fázis – elemzés (ez a dokumentum)
- Leadandók: `docs/00-elemzes.md`, `tools/check_banana_pro.sh`, `NOTICE`, `.gitignore`.
- Siker: a felhasználó jóváhagyja; **[HW]** a script lefut a Banana Pro-n, és a riport visszajön.

### 1. fázis – USB-gadget prototípus (egy pad, bemenet nélkül)
- Szükség esetén DT-overlay; `FunctionFSSink` az `ffsds4`-re, `--username` szerinti
  jogcsökkentéssel; systemd unit `User=`-rel ott, ahol lehet; a fingerprint-log elnyomása;
  a `NOTICE` kitöltése.
- Siker:
  - [PC] egységtesztek a Sinkre `dummy_hcd`-vel vagy mock-kal, és `RecordingSink`.
  - [HW] a Banana Pro `/sys/class/udc` alatt mutat egy UDC-t.
  - [HW] PC-n `lsusb` alatt megjelenik, és a HID-descriptor olvasható.
  - [HW] a PS4 13.52 felismeri, a PS gombbal belépés működik (szkriptelt gombnyomás).
  - [HW] 15 percnél tovább nem fagy le (túl a 8 percen).
  - [HW] USB-kihúzás és -visszadugás után helyreáll; hidegindítás után automatikusan elindul.
  - [HW] CPU-terhelés és késleltetés mérve.

### 2. fázis – belső modell, mapper, DS4 Protocol Engine, egy bemenet
- `pad_state`/`pad_output` alapú modell; Controller Mapper (konfigurálható); DS4 Protocol Engine
  (64 bájtos report, touch, 0x05 dekódolás); Input Manager evdev-backenddel (DualSense és DS4
  BT, `hid-playstation`); rezgés vissza `FF_RUMBLE`-lel; semleges állapot és watchdog.
- Siker:
  - [PC] reporttesztek bitpontos vektorokkal; mapper-tesztek; a watchdog teszt szerint
    X ms-on belül semlegesít.
  - [HW] minden gomb és tengely, a touchpad, a rezgés és a BT-vesztéskor beálló semleges
    állapot a PS4-en; nincs beragadás.

### 3. fázis – Device Manager, több bemenet, megbízhatóság
- Slotkezelés (1–4), hot-plug, BT-újracsatlakozás backoff-fal, padonkénti hibaizoláció
  (külön szál vagy folyamat, supervisor), USB-helyreállás, automatikus indulás, internet nélkül.
- Siker:
  - [PC] szimulált eszközök hot-plug tesztje; egy hibás forrás a többit nem állítja meg.
  - [HW] 4 bemeneti pad egyszerre a Banana Pro-n (még egy kimenettel); BT-újracsatlakozás.

### 4. fázis – négy külön PS4-játékos
- A) összetett eszköz kísérlet; hubteszt; döntés; szükség esetén `McuUartSink` és a protokoll
  specifikációja (MCU-firmware külön).
- Siker:
  - [PC] Sink-csere a bemeneti kód módosítása nélkül (ugyanaz a tesztkészlet minden Sinkkel).
  - [HW] a PS4 négy külön felhasználót/kontrollert lát; padonkénti rezgés a megfelelő
    fizikai padra jut; egy pad kihúzása a többit nem érinti.

### 5. fázis – további bemenetek és Diagnostics
- Xbox (xpad/USB, BT), általános HID (az AnyPad `generic.c` portja hidraw-ra), Switch Pro
  (`hid-nintendo` vagy hidraw + AnyPad-ébresztés), GameSir; `.map`-szerű leképezőfájlok;
  Diagnostics (strukturált log, állapotfájl, kulcsanyag nélkül).
- Siker:
  - [PC] az AnyPad tesztvektorai és fuzz-tesztje a portolt parserekre.
  - [HW] eszközönkénti kompatibilitási tábla, a felhasználó méréseivel.

### 6. fázis – magyar webes adminfelület
- Külön folyamat, nem része az adatútnak; csak állapotot olvas és konfigurációt ír, helyi
  hálózaton, hitelesítéssel; a híd nélküle is teljesen működik.
- Siker:
  - [PC] a webfolyamat leállítása nem befolyásolja a hidat (teszt).
  - [HW] felület a telefonról.

---

## Még vizsgálandó

1. **[HW]** A `tools/check_banana_pro.sh` riportja: kernelverzió, kernel-konfig (MUSB/gadget/F_FS),
   UDC, a DT `usb@1c13000` `status`/`dr_mode` értéke, ConfigFS/FunctionFS, BT-adapter, CPU/RAM.
2. Az Armbian Trixie image Banana Pro DT-je: engedélyezi-e az OTG-t, és van-e kész overlay
   (az Armbian `patch/kernel/archive/sunxi-*` könyvtárainak átnézése).
3. A Banana Pro kapcsolási rajza: az OTG VBUS-útja, a backfeed veszélye, az ID-láb bekötése.
4. A linux-sunxi wiki (USB OTG, Banana Pro, USB Gadget oldalak); ebben a környezetben nem volt
   elérhető.
5. A PS4 13.52 viselkedése: emulált, hitelesített DS4 elfogadása; az ismételt hitelesítés
   gyakorisága; a 0x05 küldési gyakorisága; a lightbar játékosonkénti színei.
6. Duplikált identitás elfogadása két vagy négy egyidejű eszköznél **[HW]**.
7. Összetett eszköz 2 vagy 4 DS4-interfésszel a PS4-en **[HW]**.
8. A PS4 Slim és USB-hub négy eszközzel **[HW]**.
9. A python-functionfs és az `ffsds4` armhf-en, Python 3.13-mal **[HW]**; az RSA-aláírás ideje
   A20-on.
10. A Linux kernel `hid-playstation` USB/BT reportjainak egybevetése az AnyPad DualSense-offszeteivel.
11. Az AP6210 BT több kontrollerrel, késleltetés **[HW]**.
12. A GP2040-CE PS4-módjának dokumentációja és forrása (hitelesítés MCU-n, RSA-idő): az MCU-s
    Sink tervezéséhez.
13. A `hvrobi/*` tükrök és az upstream repók egyezése.
