Add-Type -AssemblyName PresentationCore, PresentationFramework, WindowsBase, System.Drawing

function Generate-BrandIcon {
    param(
        [int]$Size,
        [string]$OutputPath,
        [bool]$IsMaskable = $false
    )

    $visual = [System.Windows.Media.DrawingVisual]::new()
    $dc = $visual.RenderOpen()

    # Linear Gradient from TopLeft to BottomRight: #6366F1 to #8B5CF6
    $gradBrush = [System.Windows.Media.LinearGradientBrush]::new(
        [System.Windows.Media.Color]::FromRgb(99, 102, 241),
        [System.Windows.Media.Color]::FromRgb(139, 92, 246),
        [System.Windows.Point]::new(0, 0),
        [System.Windows.Point]::new(1, 1)
    )

    if ($IsMaskable) {
        # Maskable fills entire canvas with gradient
        $dc.DrawRectangle($gradBrush, $null, [System.Windows.Rect]::new(0, 0, $Size, $Size))
        $glyphSize = $Size * 0.50
    } else {
        # Squircle with 25% corner radius
        $margin = $Size * 0.05
        $contentSize = $Size - 2 * $margin
        $radius = $contentSize * 0.25
        $rect = [System.Windows.Rect]::new($margin, $margin, $contentSize, $contentSize)
        $dc.DrawRoundedRectangle($gradBrush, $null, $rect, $radius, $radius)
        $glyphSize = $contentSize * 0.625
    }

    # Material picture_as_pdf_rounded (24x24 viewport)
    $svgPath = "M20 2H8c-1.1 0-2 .9-2 2v12c0 1.1.9 2 2 2h12c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2zm-8.5 7.5c0 .83-.67 1.5-1.5 1.5H9v1.25c0 .41-.34.75-.75.75s-.75-.34-.75-.75V7.75c0-.41.34-.75.75-.75H10c.83 0 1.5.67 1.5 1.5v1zm5 2c0 .83-.67 1.5-1.5 1.5h-2.25c-.41 0-.75-.34-.75-.75V7.75c0-.41.34-.75.75-.75H15c.83 0 1.5.67 1.5 1.5v3zm3.25-3H19v.5h1.25c.41 0 .75.34.75.75s-.34.75-.75.75H19v1.25c0 .41-.34.75-.75.75s-.75-.34-.75-.75V7.75c0-.41.34-.75.75-.75h2.5c.41 0 .75.34.75.75s-.34.75-.75.75zM9 9.5h1v-1H9v1zM3 6c-.55 0-1 .45-1 1v13c0 1.1.9 2 2 2h13c.55 0 1-.45 1-1s-.45-1-1-1H5c-.55 0-1-.45-1-1V7c0-.55-.45-1-1-1zm11 5.5h1v-3h-1v3z"
    $geom = [System.Windows.Media.Geometry]::Parse($svgPath)

    $scale = $glyphSize / 24.0
    $offsetX = ($Size - 24.0 * $scale) / 2.0
    $offsetY = ($Size - 24.0 * $scale) / 2.0

    $transGroup = [System.Windows.Media.TransformGroup]::new()
    $transGroup.Children.Add([System.Windows.Media.ScaleTransform]::new($scale, $scale))
    $transGroup.Children.Add([System.Windows.Media.TranslateTransform]::new($offsetX, $offsetY))

    $dc.PushTransform($transGroup)
    $dc.DrawGeometry([System.Windows.Media.Brushes]::White, $null, $geom)
    $dc.Pop()
    $dc.Close()

    $rtb = [System.Windows.Media.Imaging.RenderTargetBitmap]::new(
        $Size, $Size, 96, 96, [System.Windows.Media.PixelFormats]::Pbgra32
    )
    $rtb.Render($visual)

    $dir = Split-Path -Parent $OutputPath
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $encoder = [System.Windows.Media.Imaging.PngBitmapEncoder]::new()
    $encoder.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($rtb))
    $fs = [System.IO.FileStream]::new($OutputPath, [System.IO.FileMode]::Create)
    $encoder.Save($fs)
    $fs.Close()
    $fs.Dispose()
    Write-Host "Generated: $OutputPath ($Size x $Size)"
}

$webDir = "e:\Non_Office\Dev_Space\vibe_skool\freepdftoolz\src\frontend\web"
$iconsDir = "$webDir\icons"

Generate-BrandIcon -Size 512 -OutputPath "$iconsDir\Icon-512.png"
Generate-BrandIcon -Size 192 -OutputPath "$iconsDir\Icon-192.png"
Generate-BrandIcon -Size 96  -OutputPath "$iconsDir\Icon-96.png"
Generate-BrandIcon -Size 48  -OutputPath "$iconsDir\Icon-48.png"
Generate-BrandIcon -Size 32  -OutputPath "$webDir\favicon.png"

# Maskable icons
Generate-BrandIcon -Size 512 -OutputPath "$iconsDir\Icon-maskable-512.png" -IsMaskable $true
Generate-BrandIcon -Size 192 -OutputPath "$iconsDir\Icon-maskable-192.png" -IsMaskable $true

# Also brand_logo_icon.png in assets
Generate-BrandIcon -Size 512 -OutputPath "e:\Non_Office\Dev_Space\vibe_skool\freepdftoolz\src\frontend\assets\images\brand_logo_icon.png"

# Generate favicon.ico using System.Drawing
$bmp32 = [System.Drawing.Bitmap]::FromFile("$webDir\favicon.png")
$iconHandle = $bmp32.GetHicon()
$icon = [System.Drawing.Icon]::FromHandle($iconHandle)
$icoFs = [System.IO.FileStream]::new("$webDir\favicon.ico", [System.IO.FileMode]::Create)
$icon.Save($icoFs)
$icoFs.Close()
$icoFs.Dispose()
$bmp32.Dispose()
Write-Host "Generated: $webDir\favicon.ico"
