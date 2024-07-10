function request_image(url) {
  return new Promise((resolve, reject) => {
    let img = new Image()
    img.onload = () => resolve()
    img.onerror = () => reject()
    img.src = url + '?random-no-cache=' + Math.floor((1 + Math.random()) * 0x10000).toString(16)
  })
}

function ping(url, timeout = 5000) {
  return new Promise((resolve, reject) => {
    let start = Date.now()
    let response = () => {
      let delay = (Date.now() - start) + 'ms'
      resolve(delay)
    }
    request_image(url).then(response).catch(response)

    setTimeout(() => {
      // reject(Error('Timeout'))
      resolve('timeout')
    }, timeout)
  })
}

export default ping
