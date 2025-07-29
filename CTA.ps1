# ===================================================================
# PowerShell Proxy Script
# Function: Receives requests from "Cat-Catch" and forwards them
# to "AB Downloader" after reformatting.
# ===================================================================

# --- Configuration Area ---
# 1. Configure the listening address and port for receiving requests from Cat-Catch.
$listenerPrefix = "http://localhost:5000/cat_to_ab/"

# 2. API address of AB Downloader.
$abDownloaderUrl = "http://127.0.0.1:15151/start-headless-download"


# --- Main Program ---
$listener = New-Object System.Net.HttpListener

# Wrap the entire startup and execution process in a try...catch block.
try {
    $listener.Prefixes.Add($listenerPrefix)

    Write-Host "Proxy service starting..." -ForegroundColor Cyan
    Write-Host "Listening on: $($listenerPrefix)"
    Write-Host "Target URL: $($abDownloaderUrl)"
    Write-Host "Press Ctrl+C to stop the service."

    # Start listening.
    $listener.Start()

    # Infinite loop to continuously accept requests.
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $request = $context.Request
        $response = $context.Response

        # Set up a separate try/catch/finally for each request to ensure the service doesn't crash due to a single failed request.
        try {
            $reader = New-Object System.IO.StreamReader($request.InputStream, $request.ContentEncoding)
            $body = $reader.ReadToEnd()
            $catData = $body | ConvertFrom-Json

            if ($catData.action -eq 'catch') {
                Write-Host "Received media catch request: $($catData.data.name)"

                # Build the payload to be sent to AB Downloader.
                $headers = @{}
                if ($catData.data.requestHeaders.referer) { $headers.Add("Referer", $catData.data.requestHeaders.referer) }
                if ($catData.data.requestHeaders.origin)  { $headers.Add("Origin",  $catData.data.requestHeaders.origin)  }
                if ($catData.data.requestHeaders.cookie)  { $headers.Add("Cookie",  $catData.data.requestHeaders.cookie)  }

                $abPayload = @{
                    downloadSource = @{
                        link         = $catData.data.url
                        headers      = $headers
                        downloadPage = $catData.data.requestHeaders.referer
                    }
                    name = $catData.data.name
                }

                # Convert the PowerShell object to a JSON string and send the request.
                Invoke-RestMethod -Uri $abDownloaderUrl -Method Post -Body ($abPayload | ConvertTo-Json -Depth 5) -ContentType "application/json"

                Write-Host "Successfully forwarded to AB Downloader: $($catData.data.name)" -ForegroundColor Green
                $response.StatusCode = 200 # Success
            }
            else {
                Write-Host "Received non-catch request (action: $($catData.action)), ignoring." -ForegroundColor Yellow
                $response.StatusCode = 400 # Bad Request
            }
        }
        catch {
            # If an error occurs while processing a single request.
            Write-Host "Error processing request: $($_.Exception.Message)" -ForegroundColor Red
            $response.StatusCode = 500 # Internal Server Error
        }
        finally {
            # Ensure the response stream for the current request is closed.
            $response.Close()
        }
    }
}
catch {
    # Catch any terminating errors during startup or runtime (e.g., port in use, insufficient permissions).
    Write-Host "==================== FATAL ERROR ====================" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host "======================================================" -ForegroundColor Red
    Write-Host "Common causes:" -ForegroundColor Yellow
    Write-Host "1. Insufficient permissions: Please try running this script 'as Administrator'." -ForegroundColor Yellow
    Write-Host "2. Port is already in use: Try changing the port number in the script (e.g., to 5002)." -ForegroundColor Yellow
}
finally {
    # This block will execute regardless of success or failure.
    if ($listener -and $listener.IsListening) {
        $listener.Stop()
        Write-Host "Proxy service stopped."
    }
    # Add this line to pause the window, allowing the user to read error messages.
    Read-Host "Script finished or encountered an error. Press Enter to exit..."
}
