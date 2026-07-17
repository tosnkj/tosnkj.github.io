# ===================================================
# 複数フォルダのファイルを1つのフォルダにまとめるツール
# （Shift/Ctrlキーで複数フォルダを一括選択可能）
# ===================================================

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ----- すべてのダイアログの「親」となる、見えない最前面ウィンドウ -----
# これを各ダイアログのOwnerに指定することで、フォルダ選択後に次のウィンドウが
# 他のアプリ（エクスプローラーやChromeなど）の裏に隠れてしまう現象を防ぐ。
$ownerForm = New-Object System.Windows.Forms.Form
$ownerForm.StartPosition = "Manual"
$ownerForm.Location = New-Object System.Drawing.Point(-2000, -2000)
$ownerForm.Size = New-Object System.Drawing.Size(1, 1)
$ownerForm.ShowInTaskbar = $false
$ownerForm.TopMost = $true
$ownerForm.Show()
$ownerForm.Hide()

# ----- 親フォルダの中のサブフォルダを一覧表示し、複数選択させる独自ダイアログ -----
# ListBoxのMultiExtendedモードを使うため、Shift（範囲選択）・Ctrl（個別選択）が安定して動作する。
function Select-SubFolders($parentPath) {
    $subfolders = Get-ChildItem -Path $parentPath -Directory -ErrorAction SilentlyContinue | Sort-Object Name

    if ($subfolders.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show($ownerForm, "このフォルダの中にサブフォルダが見つかりませんでした。`n$parentPath", "確認") | Out-Null
        return @()
    }

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "フォルダを選択（Shiftで範囲選択／Ctrlで個別選択）"
    $form.Size = New-Object System.Drawing.Size(480, 520)
    $form.StartPosition = "CenterScreen"
    $form.MinimizeBox = $false
    $form.MaximizeBox = $false
    $form.TopMost = $true

    $label = New-Object System.Windows.Forms.Label
    $label.Text = "対象フォルダ: $parentPath"
    $label.AutoSize = $false
    $label.Size = New-Object System.Drawing.Size(440, 40)
    $label.Location = New-Object System.Drawing.Point(10, 10)
    $form.Controls.Add($label)

    $listBox = New-Object System.Windows.Forms.ListBox
    $listBox.SelectionMode = [System.Windows.Forms.SelectionMode]::MultiExtended
    $listBox.Location = New-Object System.Drawing.Point(10, 55)
    $listBox.Size = New-Object System.Drawing.Size(440, 380)
    $listBox.Font = New-Object System.Drawing.Font("Yu Gothic UI", 10)
    foreach ($sf in $subfolders) {
        $listBox.Items.Add($sf.Name) | Out-Null
    }
    $form.Controls.Add($listBox)

    $okButton = New-Object System.Windows.Forms.Button
    $okButton.Text = "選択したフォルダを追加"
    $okButton.Location = New-Object System.Drawing.Point(10, 445)
    $okButton.Size = New-Object System.Drawing.Size(200, 32)
    $okButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $form.Controls.Add($okButton)
    $form.AcceptButton = $okButton

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Text = "キャンセル"
    $cancelButton.Location = New-Object System.Drawing.Point(220, 445)
    $cancelButton.Size = New-Object System.Drawing.Size(100, 32)
    $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.Controls.Add($cancelButton)
    $form.CancelButton = $cancelButton

    $result = $form.ShowDialog($ownerForm)

    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        $selected = @()
        foreach ($item in $listBox.SelectedItems) {
            $selected += Join-Path $parentPath $item
        }
        return $selected
    } else {
        return @()
    }
}

# ----- フォルダ選択ダイアログ（コピー先用・単一選択、新規作成ボタンあり）-----
function Select-Folder($description) {
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = $description
    $dialog.ShowNewFolderButton = $true
    $result = $dialog.ShowDialog($ownerForm)
    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        return $dialog.SelectedPath
    } else {
        return $null
    }
}

# ----- 1. コピー元フォルダを複数選択 -----
$sourceFolders = @()
$continue = $true

[System.Windows.Forms.MessageBox]::Show(
    $ownerForm,
    "これから、ファイルをまとめたい元フォルダを選択します。`n`nまず、それらのフォルダが入っている『親フォルダ』を選んでください。次の画面で、その中身を一覧からShift/Ctrlキーで複数選択できます。",
    "フォルダ統合ツール",
    [System.Windows.Forms.MessageBoxButtons]::OK,
    [System.Windows.Forms.MessageBoxIcon]::Information
) | Out-Null

while ($continue) {
    $parentFolder = Select-Folder("まとめたいフォルダが入っている『親フォルダ』を選んでください")
    if ($parentFolder -eq $null) {
        if ($sourceFolders.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show($ownerForm, "フォルダが選択されませんでした。処理を終了します。")
            exit
        }
        break
    }

    $folders = Select-SubFolders($parentFolder)

    if ($folders.Count -gt 0) {
        $sourceFolders += $folders
    } else {
        if ($sourceFolders.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show($ownerForm, "フォルダが選択されませんでした。処理を終了します。")
            exit
        }
        $continue = $false
        break
    }

    $more = [System.Windows.Forms.MessageBox]::Show(
        $ownerForm,
        "他の場所にあるフォルダも追加しますか？`n（現在 $($sourceFolders.Count) 個選択済み）",
        "確認",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )
    if ($more -eq [System.Windows.Forms.DialogResult]::No) {
        $continue = $false
    }
}

$sourceFolders = $sourceFolders | Select-Object -Unique

# ----- 2. コピー先フォルダを選択 -----
[System.Windows.Forms.MessageBox]::Show(
    $ownerForm,
    "次に、まとめ先のフォルダを選択（または新規作成）してください。",
    "フォルダ統合ツール",
    [System.Windows.Forms.MessageBoxButtons]::OK,
    [System.Windows.Forms.MessageBoxIcon]::Information
) | Out-Null

$destFolder = Select-Folder("まとめ先のフォルダを選択してください（新規作成ボタンあり）")
if ($destFolder -eq $null) {
    [System.Windows.Forms.MessageBox]::Show($ownerForm, "まとめ先フォルダが選択されませんでした。処理を終了します。")
    exit
}

# ----- 3. サブフォルダも含めるか確認 -----
$includeSub = [System.Windows.Forms.MessageBox]::Show(
    $ownerForm,
    "各フォルダの中のサブフォルダのファイルも含めますか？",
    "確認",
    [System.Windows.Forms.MessageBoxButtons]::YesNo,
    [System.Windows.Forms.MessageBoxIcon]::Question
)
$recurse = ($includeSub -eq [System.Windows.Forms.DialogResult]::Yes)

# ----- 4. コピー実行 -----
$copiedCount = 0
$renamedCount = 0
$errorList = @()

foreach ($folder in $sourceFolders) {
    try {
        if ($recurse) {
            $files = Get-ChildItem -Path $folder -Recurse -File -ErrorAction Stop
        } else {
            $files = Get-ChildItem -Path $folder -File -ErrorAction Stop
        }
    } catch {
        $errorList += "読み取り失敗: $folder"
        continue
    }

    foreach ($file in $files) {
        $destPath = Join-Path $destFolder $file.Name

        if (Test-Path $destPath) {
            $baseName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
            $ext = $file.Extension
            $count = 1
            do {
                $newName = "{0}_{1}{2}" -f $baseName, $count, $ext
                $destPath = Join-Path $destFolder $newName
                $count++
            } while (Test-Path $destPath)
            $renamedCount++
        }

        try {
            Copy-Item -Path $file.FullName -Destination $destPath -ErrorAction Stop
            $copiedCount++
        } catch {
            $errorList += "コピー失敗: $($file.FullName)"
        }
    }
}

# ----- 5. 結果を表示 -----
$message = "完了しました。`n`n選択したフォルダ数: $($sourceFolders.Count)`nコピーしたファイル数: $copiedCount`nリネームしたファイル数: $renamedCount`nまとめ先: $destFolder"
if ($errorList.Count -gt 0) {
    $message += "`n`n--- エラー ---`n" + ($errorList -join "`n")
}

[System.Windows.Forms.MessageBox]::Show($ownerForm, $message, "処理結果", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null

# エクスプローラーでまとめ先フォルダを開く
Start-Process explorer.exe $destFolder

# 見えない親ウィンドウを片付ける
$ownerForm.Close()