module.exports = (content) => {
  return `<!DOCTYPE html
  PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">

<html xmlns="http://www.w3.org/1999/xhtml">

<head>
  <meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
</head>

<body style="margin: 0; padding: 0;text-align: center;">
  <table border="0" cellpadding="0" cellspacing="0" width="100%">
    <tr>
      <td>
        <h3 style="font-size: 18px;color: #5992D3;padding:0 0 0 10px;">
          ${ content }
        </h3>
      </td>
    </tr>
  </table>
</body>

</html>
  `
}