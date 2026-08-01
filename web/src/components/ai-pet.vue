<template>
  <svg
    class="ai_pet"
    :class="[`is_${ state }`, { 'is_hovered': hovered }]"
    viewBox="0 0 64 64"
    fill="none"
    xmlns="http://www.w3.org/2000/svg"
    aria-hidden="true"
  >
    <g class="pet_body">
      <path d="M22 35H42V38H46V55H43V58H21V55H18V38H22V35Z" fill="#202536" />
      <path d="M23 37H41V39H44V54H41V56H23V54H20V40H23V37Z" fill="#FFB916" />
      <path d="M23 37H41V40H23V37Z" fill="#FFD040" />
      <path d="M20 47H23V54H20V47ZM41 47H44V54H41V47Z" fill="#E98709" />
      <path d="M28 46H36V54H28V46Z" fill="#282D40" />
      <path d="M30 48H34V52H30V48Z" fill="#8658F6" />
      <path class="pet_core" d="M31 48H33V50H31V48Z" fill="#E9D8FF" />
    </g>

    <g class="pet_arm pet_arm_left">
      <path d="M16 39H21V51H16V39Z" fill="#E98709" />
      <path d="M14 41H19V52H14V41Z" fill="#FFBB18" />
      <path d="M12 49H17V54H12V49Z" fill="#2A3042" />
      <path d="M13 50H15V52H13V50Z" fill="#596176" />
    </g>
    <g class="pet_arm pet_arm_right">
      <path d="M43 39H48V51H43V39Z" fill="#E98709" />
      <path d="M45 41H50V52H45V41Z" fill="#FFBB18" />
      <path d="M48 49H53V54H48V49Z" fill="#2A3042" />
      <path d="M50 50H52V52H50V50Z" fill="#596176" />
    </g>

    <g class="pet_legs">
      <path d="M23 55H31V61H23V55ZM34 55H42V61H34V55Z" fill="#252A3B" />
      <path d="M21 59H31V63H21V59ZM34 59H44V63H34V59Z" fill="#181D2B" />
      <path d="M24 56H30V59H24V56ZM35 56H41V59H35V56Z" fill="#FFC62A" />
      <path d="M22 61H31V63H22V61ZM34 61H43V63H34V61Z" fill="#0F1320" />
      <path d="M22 59H25V60H22V59ZM35 59H38V60H35V59Z" fill="#616A7E" />
    </g>

    <g class="pet_head">
      <path d="M17 2H47V4H53V7H57V11H60V30H57V34H53V37H11V34H7V30H4V11H7V7H11V4H17V2Z" fill="#1A1F2E" />
      <path d="M18 4H46V6H52V9H55V12H58V29H55V32H51V35H13V32H9V29H6V12H9V9H12V6H18V4Z" fill="#FFB817" />
      <path d="M19 6H45V8H50V10H53V13H56V28H53V31H49V33H15V31H11V28H8V13H11V10H14V8H19V6Z" fill="#FFC72E" />
      <path d="M19 6H44V8H49V10H17V12H13V15H10V12H13V9H19V6Z" fill="#FFE05A" />
      <path d="M15 11H49V13H52V31H49V33H15V31H12V13H15V11Z" fill="#171C29" />
      <path d="M16 13H48V15H50V29H48V31H16V29H14V15H16V13Z" fill="#222938" />
      <path d="M17 8H21V10H19V12H16V10H17V8Z" fill="#FFF7C2" />

      <g class="pet_face pet_face_normal">
        <path d="M20 18H23V21H26V24H29V27H26V30H23V33H20V30H23V27H26V24H23V21H20V18Z" fill="#FFD040" />
        <path d="M33 28H43V31H33V28Z" fill="#FFD040" />
      </g>
      <g class="pet_face pet_face_idle">
        <path d="M19 23H22V26H25V23H28V26H25V28H22V26H19V23ZM35 23H38V26H41V23H44V26H41V28H38V26H35V23Z" fill="#FFE276" />
      </g>
      <g class="pet_face pet_face_happy">
        <path d="M18 27H21V24H24V22H27V24H30V29H27V26H24V25H21V29H18V27ZM34 27H37V24H40V22H43V24H46V29H43V26H40V25H37V29H34V27Z" fill="#FFF0A0" />
      </g>

      <path d="M55 13H59V16H61V28H59V31H55V13Z" fill="#202536" />
      <path d="M56 15H59V29H56V15Z" fill="#E78808" />
      <path d="M58 17H61V27H58V17Z" fill="#6F42E8" />
      <path d="M59 18H61V22H59V18Z" fill="#B698FF" />
    </g>
  </svg>
</template>

<script setup>
defineProps({
  state: {
    type: String,
    default: 'normal',
    validator: value => ['normal', 'idle', 'working', 'happy',].includes(value)
  },
  hovered: { type: Boolean, default: false }
})
</script>

<style scoped lang="scss">
.ai_pet {
  display: block;
  overflow: visible;
  shape-rendering: geometricPrecision;

  .pet_face_idle,
  .pet_face_happy {
    display: none;
  }

  &.is_idle {
    .pet_face_normal { display: none; }
    .pet_face_idle { display: block; }
  }

  &.is_happy {
    .pet_face_normal { display: none; }
    .pet_face_happy { display: block; }

    .pet_arm_left {
      transform: translate(-3px, -7px) rotate(-38deg);
      animation: pet_happy_left 0.64s cubic-bezier(0.45, 0, 0.3, 1) infinite;
    }

    .pet_arm_right {
      transform: translate(3px, -7px) rotate(38deg);
      animation: pet_happy_right 0.64s cubic-bezier(0.45, 0, 0.3, 1) infinite;
    }

    .pet_head { animation: pet_happy_head 0.64s ease-in-out infinite; }
    .pet_legs { animation: pet_happy_legs 0.64s ease-in-out infinite; }
  }

  &.is_working {
    .pet_face_normal {
      filter: drop-shadow(0 0 2px rgba(255, 208, 64, 0.9));
    }

    .pet_core {
      animation: pet_core_pulse 0.7s steps(2, end) infinite;
    }

    .pet_arm_left {
      animation: pet_work_left 0.72s ease-in-out infinite;
    }

    .pet_arm_right {
      animation: pet_work_right 0.72s ease-in-out infinite;
    }
  }

  &.is_hovered:not(.is_working):not(.is_happy) {
    .pet_arm_left { animation: pet_hover_left 0.68s cubic-bezier(0.2, 0.75, 0.3, 1); }
    .pet_arm_right { animation: pet_hover_right 0.68s cubic-bezier(0.2, 0.75, 0.3, 1); }
    .pet_head { animation: pet_hover_head 0.68s cubic-bezier(0.2, 0.75, 0.3, 1); }
    .pet_legs { animation: pet_hover_legs 0.68s cubic-bezier(0.2, 0.75, 0.3, 1); }
  }
}

.pet_arm,
.pet_head,
.pet_legs {
  transform-box: view-box;
}

.pet_arm_left { transform-origin: 20px 40px; }
.pet_arm_right { transform-origin: 44px 40px; }
.pet_head { transform-origin: 32px 35px; }
.pet_legs { transform-origin: 32px 56px; }

@keyframes pet_work_left {
  0%, 100% { transform: translateY(0); }
  50% { transform: translate(-2px, -5px) rotate(-18deg); }
}

@keyframes pet_work_right {
  0%, 100% { transform: translate(2px, -5px) rotate(18deg); }
  50% { transform: translateY(0); }
}

@keyframes pet_happy_left {
  0%, 100% { transform: translate(-3px, -7px) rotate(-38deg); }
  50% { transform: translate(-5px, -9px) rotate(-52deg); }
}

@keyframes pet_happy_right {
  0%, 100% { transform: translate(3px, -7px) rotate(38deg); }
  50% { transform: translate(5px, -9px) rotate(52deg); }
}

@keyframes pet_happy_head {
  0%, 100% { transform: translateY(0) rotate(-2deg); }
  50% { transform: translateY(-2px) rotate(2deg); }
}

@keyframes pet_happy_legs {
  0%, 100% { transform: translateY(0) scaleY(1); }
  50% { transform: translateY(2px) scaleY(0.9); }
}

@keyframes pet_hover_left {
  0%, 100% { transform: translateY(0) rotate(0); }
  30%, 60% { transform: translate(-4px, -8px) rotate(-46deg); }
  45% { transform: translate(-5px, -9px) rotate(-58deg); }
}

@keyframes pet_hover_right {
  0%, 100% { transform: translateY(0) rotate(0); }
  35% { transform: translate(3px, -5px) rotate(26deg); }
  65% { transform: translate(2px, -6px) rotate(34deg); }
}

@keyframes pet_hover_head {
  0%, 100% { transform: rotate(0); }
  32% { transform: translateY(-1px) rotate(-4deg); }
  62% { transform: rotate(3deg); }
}

@keyframes pet_hover_legs {
  0%, 100% { transform: translateY(0) scaleY(1); }
  30%, 62% { transform: translateY(3px) scaleY(0.88); }
  82% { transform: translateY(-1px) scaleY(1.06); }
}

@keyframes pet_core_pulse {
  0%, 100% { fill: #E9D8FF; }
  50% { fill: #FFFFFF; }
}

@media (prefers-reduced-motion: reduce) {
  .ai_pet .pet_arm,
  .ai_pet .pet_head,
  .ai_pet .pet_legs,
  .ai_pet .pet_core {
    animation: none !important;
  }
}
</style>
