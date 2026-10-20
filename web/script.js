// Простая анимация печатающегося текста
const text = "Суверенный стек разработки.";
const element = document.getElementById("typing-text");
let index = 0;

function type() {
    if (index < text.length) {
        element.textContent = text.slice(0, index + 1);
        index++;
        setTimeout(type, 100);
    }
}

// Очищаем и запускаем анимацию
element.textContent = "";
setTimeout(type, 500);

// Плавная прокрутка
document.querySelectorAll('nav a').forEach(anchor => {
    anchor.addEventListener('click', function (e) {
        if(this.getAttribute('href').startsWith('#')) {
            e.preventDefault();
            document.querySelector(this.getAttribute('href')).scrollIntoView({
                behavior: 'smooth'
            });
        }
    });
});
