import svgIcon from '../components/svg-icon.vue'
import tooltip from '../components/tooltip.vue'

export default (app) => {
  app.component('SvgIcon', svgIcon)
  app.component('Tooltip', tooltip)
}
