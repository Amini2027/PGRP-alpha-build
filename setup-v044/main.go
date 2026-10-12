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
	"unicode/utf16"
	"unsafe"
)

// A standalone Windows installer: the original, proven OpenSAMP launcher,
// the new v0.4.4 Client.Native.dll and the install UI ship inside this EXE.
//go:embed payload/opensamp.exe payload/Client.Native.dll install.ps1
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
	work, err := os.MkdirTemp("", "PGRP_Alpha_v044_Setup_")
	if err != nil { messageBox("PGRP Setup failed", err.Error(), 0x10); os.Exit(1) }
	defer os.RemoveAll(work)
	assets := filepath.Join(work, "payload")
	if err = os.MkdirAll(assets, 0700); err != nil {
		messageBox("PGRP Setup failed", err.Error(), 0x10); os.Exit(1)
	}
	paths := []struct{ src, dest string }{
		{"payload/opensamp.exe", filepath.Join(assets,"opensamp.exe")},
		{"payload/Client.Native.dll", filepath.Join(assets,"Client.Native.dll")},
		{"install.ps1", filepath.Join(work,"install.ps1")},
	}
	var hashes []string
	for _, p := range paths {
		sum, e := writeEmbedded(p.src, p.dest)
		if e != nil { messageBox("PGRP Setup failed", e.Error(), 0x10); os.Exit(1) }
		hashes = append(hashes, p.src+" "+sum)
	}
	if len(os.Args) > 1 && os.Args[1] == "--verify" {
		fmt.Println("PGRP Alpha v0.4.4 embedded payload verification")
		fmt.Println(strings.Join(hashes,"\n"))
		return
	}

	// STA is mandatory for the WinForms browse dialog.
	args := []string{"-NoProfile","-NonInteractive","-STA","-ExecutionPolicy","Bypass","-File",
		filepath.Join(work,"install.ps1"),"-AssetsDir",assets}
	if len(os.Args) > 1 {
		args = append(args,os.Args[1:]...)
	}
	cmd := exec.Command("powershell.exe",args...)
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
	if err = cmd.Run(); err != nil {
		messageBox("PGRP Setup", "Installer finished with an error.\nSee %TEMP%\\PGRP_v044_Setup.log for details.\n\n"+err.Error(),0x10)
		os.Exit(1)
	}
}

var _ = utf16.RuneLen
