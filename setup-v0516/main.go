package main

import (
	"crypto/sha256"
	"embed"
	"encoding/hex"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"unsafe"
)

// A standalone Windows installer: the original, proven OpenSAMP launcher,
// the new v0.5.16 Client.Native.dll and the install UI ship inside this EXE.
//go:embed payload/opensamp.exe payload/Client.Native.dll payload/PGRPLauncher.exe payload/vc_redist.x86.exe install.ps1
var resources embed.FS

var (
	user32       = syscall.NewLazyDLL("user32.dll")
	messageBoxW  = user32.NewProc("MessageBoxW")
)

func messageBox(title, body string, flags uintptr) {
	t, _ := syscall.UTF16PtrFromString(title)
	b, _ := syscall.UTF16PtrFromString(body)
	messageBoxW.Call(0, uintptr(unsafe.Pointer(b)), uintptr(unsafe.Pointer(t)), flags)
}

func writeEmbedded(name, path string) (string, error) {
	data, err := resources.ReadFile(name)
	if err != nil { return "", fmt.Errorf("embedded %s: %w", name, err) }
	if err = os.WriteFile(path, data, 0600); err != nil { return "", err }
	sum := sha256.Sum256(data)
	return strings.ToUpper(hex.EncodeToString(sum[:])), nil
}

func main() {
	work, err := os.MkdirTemp("", "PGRP_Alpha_v0516_Setup_")
	if err != nil { messageBox("PGRP Setup failed", err.Error(), 0x10); os.Exit(1) }
	defer os.RemoveAll(work)
	assets := filepath.Join(work, "payload")
	if err = os.MkdirAll(assets, 0700); err != nil {
		messageBox("PGRP Setup failed", err.Error(), 0x10); os.Exit(1)
	}
	paths := []struct{ src, dest string }{
		{"payload/opensamp.exe", filepath.Join(assets,"opensamp.exe")},
		{"payload/Client.Native.dll", filepath.Join(assets,"Client.Native.dll")},
		{"payload/PGRPLauncher.exe", filepath.Join(assets,"PGRPLauncher.exe")},
		{"payload/vc_redist.x86.exe", filepath.Join(assets,"vc_redist.x86.exe")},
		{"install.ps1", filepath.Join(work,"install.ps1")},
	}
	var hashes []string
	for _, p := range paths {
		sum, e := writeEmbedded(p.src, p.dest)
		if e != nil { messageBox("PGRP Setup failed", e.Error(), 0x10); os.Exit(1) }
		hashes = append(hashes, p.src+" "+sum)
	}
	if len(os.Args) > 1 && os.Args[1] == "--verify" {
		fmt.Println("PGRP v0.5.16 combined setup embedded payload verification")
		fmt.Println(strings.Join(hashes,"\n"))
		return
	}

	// IMPORTANT: HideWindow:true sets STARTF_USESHOWWINDOW/SW_HIDE. The
	// first ShowWindow call in WinForms then inherits SW_HIDE from STARTUPINFO,
	// so the installer runs invisibly. CREATE_NO_WINDOW hides only the
	// *PowerShell console* without suppressing the WinForms GUI itself.
	args := []string{"-NoProfile","-STA","-ExecutionPolicy","Bypass","-File",
		filepath.Join(work,"install.ps1"),"-AssetsDir",assets}
	if len(os.Args) > 1 {
		args = append(args,os.Args[1:]...)
	}
	cmd := exec.Command("powershell.exe",args...)
	const createNoWindow = 0x08000000
	cmd.SysProcAttr = &syscall.SysProcAttr{CreationFlags: createNoWindow}
	trace, traceErr := os.OpenFile(filepath.Join(os.TempDir(), "PGRP_v0516_Setup_Boot.log"), os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0600)
	if traceErr == nil {
		defer trace.Close()
		fmt.Fprintln(trace, "Starting PowerShell WinForms installer (CREATE_NO_WINDOW; no SW_HIDE)")
		cmd.Stdout = trace
		cmd.Stderr = trace
	}
	if err = cmd.Run(); err != nil {
		if trace != nil { fmt.Fprintln(trace, "PowerShell process error: "+err.Error()) }
		messageBox("PGRP Setup", "Installer finished with an error.\nCheck %TEMP%\\PGRP_v0516_Setup_Boot.log and PGRP_v0516_Setup.log\n\n"+err.Error(),0x10)
		os.Exit(1)
	}
}

