module.exports = (content) => {
  return `<!DOCTYPE html>
    <html>
    <head>
        <style>
            body {
                font-family: Arial, sans-serif;
                margin: 15px 5px;
                color: #333;
                background-color: #f4f4f4;
                line-height: 1.6;
            }
            .container {
                background-color: #fff;
                padding: 20px;
                border-radius: 8px;
                box-shadow: 0 0 10px rgba(0, 0, 0, 0.1);
            }
            h1 {
                color: #4CAF50;
            }
            p {
                margin: 12px 0;
            }
            .footer {
                text-align: center;
                font-size: 0.9em;
                color: #777;
            }
        </style>
    </head>
    <body>
        <div class="container">
            <p>${ content }</p>
            <p class="footer">通知发送时间: ${ new Date() }</p>
        </div>
    </body>
    </html>
  `
}