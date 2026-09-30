import ctypes
import json
import os
import threading
import time
import tkinter as tk
from tkinter import ttk, messagebox

import pynmea2
import serial

APP_NAME = "GPS 多程式分流器"
CONFIG_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "gps_splitter_config.json")
BAUDRATES = [4800, 9600, 19200, 38400, 57600, 115200]

try:
    ctypes.windll.shcore.SetProcessDpiAwareness(1)
except Exception:
    try:
        ctypes.windll.user32.SetProcessDPIAware()
    except Exception:
        pass


class GPSSplitter:
    def __init__(self, root):
        self.root = root
        self.root.title(APP_NAME)
        sw, sh = root.winfo_screenwidth(), root.winfo_screenheight()
        w, h = min(1000, sw - 80), min(820, sh - 100)
        root.geometry(f"{w}x{h}+{max(0,(sw-w)//2)}+{max(0,(sh-h)//2)}")
        root.minsize(820, 650)

        self.running = False
        self.gps_serial = None
        self.output_serials = {}
        self.detected_baud = None
        self.nmea_buffer = ""
        self.latitude = "-"
        self.longitude = "-"
        self.satellites = "-"
        self.speed = None
        self.fix_status = "-"
        self.rx_bytes = 0
        self.tx_bytes = [0] * 5
        self.number_vcmd = (root.register(self.only_number), "%P")

        self.build_ui()
        self.load_config()
        self.root.protocol("WM_DELETE_WINDOW", self.on_close)
        self.update_stats()

    def only_number(self, value):
        return value == "" or value.isdigit()

    def com_name(self, value):
        value = value.strip()
        return f"COM{value}" if value else ""

    def build_ui(self):
        self.root.columnconfigure(0, weight=1)
        self.root.rowconfigure(1, weight=1)

        title = tk.Label(self.root, text=APP_NAME, font=("Microsoft JhengHei", 22, "bold"))
        title.grid(row=0, column=0, pady=(12, 8))

        body = ttk.Frame(self.root)
        body.grid(row=1, column=0, sticky="nsew", padx=15)
        body.columnconfigure(0, weight=1)

        src = ttk.LabelFrame(body, text=" GPS 來源 ", padding=(12, 8))
        src.grid(row=0, column=0, sticky="ew", pady=4)
        ttk.Label(src, text="GPS COM：COM").pack(side="left")
        self.source_port = ttk.Entry(src, width=7, validate="key", validatecommand=self.number_vcmd)
        self.source_port.pack(side="left", padx=(3, 18))
        ttk.Button(src, text="測試 / 自動偵測 Baud", command=self.start_baud_scan).pack(side="left")

        info_row = ttk.Frame(body)
        info_row.grid(row=1, column=0, sticky="ew", pady=4)
        info_row.columnconfigure(0, weight=1)
        info_row.columnconfigure(1, weight=1)

        status = ttk.LabelFrame(info_row, text=" GPS 狀態 ", padding=(12, 8))
        status.grid(row=0, column=0, sticky="nsew", padx=(0,4))
        self.gps_status_label = tk.Label(status, text="● 未連線", font=("Microsoft JhengHei", 12))
        self.gps_status_label.pack(anchor="w", pady=2)
        self.baud_label = tk.Label(status, text="Baud Rate：尚未偵測")
        self.baud_label.pack(anchor="w", pady=2)
        self.fix_label = tk.Label(status, text="定位：-")
        self.fix_label.pack(anchor="w", pady=2)

        gpsinfo = ttk.LabelFrame(info_row, text=" GPS 資訊 ", padding=(12, 8))
        gpsinfo.grid(row=0, column=1, sticky="nsew", padx=(4,0))
        self.lat_label = tk.Label(gpsinfo, text="緯度：-", font=("Consolas", 10))
        self.lon_label = tk.Label(gpsinfo, text="經度：-", font=("Consolas", 10))
        self.sat_label = tk.Label(gpsinfo, text="衛星：-")
        self.speed_label = tk.Label(gpsinfo, text="速度：- km/h")
        for widget in (self.lat_label, self.lon_label, self.sat_label, self.speed_label):
            widget.pack(anchor="w", pady=1)

        out = ttk.LabelFrame(body, text=" GPS 輸出（最多 5 路） ", padding=(12, 6))
        out.grid(row=2, column=0, sticky="ew", pady=4)
        self.output_enabled, self.output_ports, self.output_status_labels = [], [], []
        defaults = ["5","6","7","8","9"]
        ttk.Label(out, text="啟用", width=10).grid(row=0, column=0)
        ttk.Label(out, text="輸出 COM", width=14).grid(row=0, column=1)
        ttk.Label(out, text="狀態", width=32, anchor="w").grid(row=0, column=2)
        for i, d in enumerate(defaults):
            enabled = tk.BooleanVar(value=False)
            ttk.Checkbutton(out, text=f"輸出 {i+1}", variable=enabled).grid(row=i+1, column=0, sticky="w", pady=2)
            pf = ttk.Frame(out)
            pf.grid(row=i+1, column=1, sticky="w", pady=2)
            ttk.Label(pf, text="COM").pack(side="left")
            entry = ttk.Entry(pf, width=6, validate="key", validatecommand=self.number_vcmd)
            entry.insert(0, d)
            entry.pack(side="left", padx=(3,0))
            sl = tk.Label(out, text="未啟用", width=32, anchor="w")
            sl.grid(row=i+1, column=2, sticky="w", padx=8)
            self.output_enabled.append(enabled)
            self.output_ports.append(entry)
            self.output_status_labels.append(sl)

        buttons = ttk.Frame(body)
        buttons.grid(row=3, column=0, pady=6)
        ttk.Button(buttons, text="開始分流", width=14, command=self.start_splitter).pack(side="left", padx=8)
        ttk.Button(buttons, text="停止", width=14, command=self.stop_splitter).pack(side="left", padx=8)

        traffic = ttk.LabelFrame(self.root, text=" 資料狀態 ", padding=(10,5))
        traffic.grid(row=2, column=0, sticky="ew", padx=15, pady=(4,2))
        self.rx_label = tk.Label(traffic, text="RX：0 bytes/s", font=("Consolas",10))
        self.rx_label.pack(side="left", padx=8)
        self.tx_label = tk.Label(traffic, text="TX：0 / 0 / 0 / 0 / 0 bytes/s", font=("Consolas",10))
        self.tx_label.pack(side="left", padx=25)

        logf = ttk.LabelFrame(self.root, text=" 系統訊息 ", padding=5)
        logf.grid(row=3, column=0, sticky="ew", padx=15, pady=(2,10))
        logf.columnconfigure(0, weight=1)
        self.log_box = tk.Text(logf, height=7, state="disabled", font=("Consolas",9), wrap="word")
        self.log_box.grid(row=0, column=0, sticky="ew")
        sb = ttk.Scrollbar(logf, orient="vertical", command=self.log_box.yview)
        sb.grid(row=0, column=1, sticky="ns")
        self.log_box.configure(yscrollcommand=sb.set)

    def log(self, text):
        now = time.strftime("%H:%M:%S")
        def add():
            try:
                self.log_box.config(state="normal")
                self.log_box.insert("end", f"[{now}] {text}\n")
                self.log_box.see("end")
                self.log_box.config(state="disabled")
            except Exception:
                pass
        self.root.after(0, add)

    def start_baud_scan(self):
        n = self.source_port.get().strip()
        if not n:
            messagebox.showwarning("提示", "請輸入 GPS COM 編號")
            return
        threading.Thread(target=self.detect_baud, args=(self.com_name(n),), daemon=True).start()

    def detect_baud(self, port):
        self.log(f"開始偵測 {port} Baud Rate...")
        self.root.after(0, lambda: self.gps_status_label.config(text="● 偵測中..."))
        for baud in BAUDRATES:
            self.log(f"測試 {port} @ {baud}")
            try:
                ser = serial.Serial(port, baud, bytesize=8, parity="N", stopbits=1, timeout=0.8)
                ser.reset_input_buffer()
                start, valid = time.time(), 0
                while time.time() - start < 4:
                    raw = ser.readline()
                    if not raw:
                        continue
                    text = raw.decode("ascii", errors="ignore").strip()
                    if text.startswith("$") and any(x in text for x in ("RMC","GGA","GLL")):
                        valid += 1
                    if valid >= 2:
                        ser.close()
                        time.sleep(1.0)
                        self.detected_baud = baud
                        self.root.after(0, lambda b=baud: self.baud_label.config(text=f"Baud Rate：{b}"))
                        self.root.after(0, lambda: self.gps_status_label.config(text="● GPS 已找到"))
                        self.log(f"成功：{port} @ {baud}")
                        self.save_config()
                        return
                ser.close()
            except Exception as e:
                self.log(f"{baud}：{e}")
        self.detected_baud = None
        self.root.after(0, lambda: self.gps_status_label.config(text="● 找不到 GPS"))
        self.root.after(0, lambda: self.baud_label.config(text="Baud Rate：偵測失敗"))

    def start_splitter(self):
        if self.running:
            return
        source_n = self.source_port.get().strip()
        if not source_n:
            messagebox.showwarning("錯誤", "請輸入 GPS COM 編號")
            return
        if not self.detected_baud:
            messagebox.showwarning("錯誤", "請先執行 Baud 自動偵測")
            return

        source = self.com_name(source_n)
        seen = set()
        for i in range(5):
            if not self.output_enabled[i].get():
                continue
            n = self.output_ports[i].get().strip()
            if not n:
                messagebox.showwarning("錯誤", f"輸出 {i+1} 尚未輸入 COM 編號")
                return
            p = self.com_name(n)
            if p == source:
                messagebox.showwarning("錯誤", f"輸出 {i+1} 不可與 GPS來源 {source} 相同")
                return
            if p in seen:
                messagebox.showwarning("錯誤", f"{p} 被重複使用")
                return
            seen.add(p)

        self.running = True
        self.save_config()
        threading.Thread(target=self.main_worker, daemon=True).start()

    def main_worker(self):
        source = self.com_name(self.source_port.get())
        while self.running:
            try:
                self.log(f"連接 GPS：{source} @ {self.detected_baud}")
                self.gps_serial = serial.Serial(source, self.detected_baud, bytesize=8, parity="N", stopbits=1, timeout=0.2)
                self.gps_serial.reset_input_buffer()
                self.open_outputs()
                self.root.after(0, lambda: self.gps_status_label.config(text="● 已連線"))
                while self.running:
                    waiting = self.gps_serial.in_waiting
                    if waiting:
                        data = self.gps_serial.read(waiting)
                        self.rx_bytes += len(data)
                        self.forward_data(data)
                        self.parse_nmea(data)
                    else:
                        time.sleep(0.01)
            except Exception as e:
                self.log(f"GPS 斷線：{e}")
                self.root.after(0, lambda: self.gps_status_label.config(text="● GPS 已斷線"))
                self.close_ports()
                if self.running:
                    self.log("2 秒後自動重新連線...")
                    time.sleep(2)
        self.close_ports()

    def open_outputs(self):
        self.output_serials = {}
        for i in range(5):
            if not self.output_enabled[i].get():
                self.root.after(0, lambda n=i: self.output_status_labels[n].config(text="未啟用"))
                continue
            port = self.com_name(self.output_ports[i].get())
            try:
                ser = serial.Serial(port, self.detected_baud, bytesize=8, parity="N", stopbits=1, timeout=0, write_timeout=0.5)
                self.output_serials[i] = ser
                self.root.after(0, lambda n=i, p=port: self.output_status_labels[n].config(text=f"● 已開啟 {p}"))
                self.log(f"輸出 {i+1}：{port} 已開啟")
            except Exception as e:
                self.root.after(0, lambda n=i: self.output_status_labels[n].config(text="● 開啟失敗"))
                self.log(f"輸出 {i+1} {port} 開啟失敗：{e}")

    def forward_data(self, data):
        dead = []
        for i, ser in list(self.output_serials.items()):
            try:
                ser.write(data)
                self.tx_bytes[i] += len(data)
            except Exception as e:
                self.log(f"輸出 {i+1} 發生錯誤：{e}")
                dead.append(i)
        for i in dead:
            try:
                self.output_serials[i].close()
            except Exception:
                pass
            self.output_serials.pop(i, None)
            self.root.after(0, lambda n=i: self.output_status_labels[n].config(text="● 已斷線"))

    def parse_nmea(self, data):
        try:
            self.nmea_buffer += data.decode("ascii", errors="ignore")
            if len(self.nmea_buffer) > 10000:
                self.nmea_buffer = self.nmea_buffer[-5000:]
            while "\n" in self.nmea_buffer:
                line, self.nmea_buffer = self.nmea_buffer.split("\n", 1)
                line = line.strip()
                if not line.startswith("$"):
                    continue
                try:
                    msg = pynmea2.parse(line)
                    if isinstance(msg, pynmea2.types.talker.RMC):
                        self.fix_status = "有效" if msg.status == "A" else "無效"
                        if msg.latitude:
                            self.latitude = msg.latitude
                        if msg.longitude:
                            self.longitude = msg.longitude
                        try:
                            self.speed = float(msg.spd_over_grnd or 0) * 1.852
                        except Exception:
                            pass
                    elif isinstance(msg, pynmea2.types.talker.GGA):
                        try:
                            self.fix_status = "有效" if int(msg.gps_qual or 0) > 0 else "無效"
                            self.satellites = int(msg.num_sats or 0)
                        except Exception:
                            pass
                        if msg.latitude:
                            self.latitude = msg.latitude
                        if msg.longitude:
                            self.longitude = msg.longitude
                    self.update_gps_ui()
                except Exception:
                    pass
        except Exception:
            pass

    def update_gps_ui(self):
        lat = f"{self.latitude:.8f}" if isinstance(self.latitude, float) else str(self.latitude)
        lon = f"{self.longitude:.8f}" if isinstance(self.longitude, float) else str(self.longitude)
        spd = f"{self.speed:.1f}" if isinstance(self.speed, (int,float)) else "-"
        self.root.after(0, lambda: self.lat_label.config(text=f"緯度：{lat}"))
        self.root.after(0, lambda: self.lon_label.config(text=f"經度：{lon}"))
        self.root.after(0, lambda: self.sat_label.config(text=f"衛星：{self.satellites}"))
        self.root.after(0, lambda: self.speed_label.config(text=f"速度：{spd} km/h"))
        self.root.after(0, lambda: self.fix_label.config(text=f"定位：{self.fix_status}"))

    def stop_splitter(self):
        self.running = False
        self.close_ports()
        self.gps_status_label.config(text="● 已停止")
        self.log("GPS 分流已停止")

    def close_ports(self):
        try:
            if self.gps_serial and self.gps_serial.is_open:
                self.gps_serial.close()
        except Exception:
            pass
        self.gps_serial = None
        for ser in list(self.output_serials.values()):
            try:
                ser.close()
            except Exception:
                pass
        self.output_serials = {}

    def update_stats(self):
        rx, tx = self.rx_bytes, self.tx_bytes[:]
        self.rx_bytes, self.tx_bytes = 0, [0]*5
        self.rx_label.config(text=f"RX：{rx} bytes/s")
        self.tx_label.config(text="TX：" + " / ".join(map(str, tx)) + " bytes/s")
        self.root.after(1000, self.update_stats)

    def save_config(self):
        cfg = {
            "source": self.source_port.get(),
            "baud": self.detected_baud,
            "outputs": [{"enabled": self.output_enabled[i].get(), "port": self.output_ports[i].get()} for i in range(5)]
        }
        try:
            with open(CONFIG_FILE, "w", encoding="utf-8") as f:
                json.dump(cfg, f, indent=2, ensure_ascii=False)
        except Exception:
            pass

    def load_config(self):
        self.source_port.insert(0, "11")
        defaults = ["5","6","7","8","9"]
        if not os.path.exists(CONFIG_FILE):
            return
        try:
            with open(CONFIG_FILE, "r", encoding="utf-8") as f:
                cfg = json.load(f)
            self.source_port.delete(0, "end")
            self.source_port.insert(0, cfg.get("source") or "11")
            self.detected_baud = cfg.get("baud")
            if self.detected_baud:
                self.baud_label.config(text=f"Baud Rate：{self.detected_baud}")
            for i, item in enumerate(cfg.get("outputs", [])[:5]):
                self.output_enabled[i].set(item.get("enabled", False))
                self.output_ports[i].delete(0, "end")
                self.output_ports[i].insert(0, item.get("port") or defaults[i])
        except Exception as e:
            self.log(f"設定檔讀取失敗：{e}")

    def on_close(self):
        self.running = False
        self.save_config()
        self.close_ports()
        self.root.destroy()


if __name__ == "__main__":
    root = tk.Tk()
    GPSSplitter(root)
    root.mainloop()
