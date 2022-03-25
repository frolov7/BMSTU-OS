.386p

descr struc
    limit  dw 0 ; Номер последнего байта сегмента (Тут 16 бит).
    base_l dw 0 ; База сегмента, биты 0..15 определяет начальный линейный адрес сегмента
    base_m db 0 ; База сегмента, биты 16..23
    attr_1 db 0 ;байт атрибутов 1
    arrt_2 db 0 ;граница(биты 16..19) и атрибуы 2, старшие 4 бита номера последнего байта сегмента 
    base_h db 0 ;База, биты 24..31
descr ends

intr struc
    offs_l dw 0 ; смещение в сегменте, нижняя часть
    sel    dw 0 ;селектор сегмента с кодом прерывания
    rsrv   db 0 ; счётчик, не используется в программе
    attr   db 0 ; атрибуты
    offs_h dw 0 ; смещение в сегменте, верхняя часть
intr ends

pm_seg	SEGMENT PARA PUBLIC 'CODE' USE32 
    assume cs:pm_seg
    ; Таблица глобальных дескрипторов GDT - Адресация программы
    gdt label byte
    gdt_null descr <> ; нулевой дескриптор
    gdt_data descr <0FFFFh,0,0,10010010b,0CFh,0> ; 32-битный 4-гигабайтный сегмент с базой = 0
	; в реальном режиме макс. доступный физ. адрес 1 МБ = 2^20 байтов из-за разрядности шины адреса (20)
    gdt_code16 descr <rm_seg_size-1,0,0,98h,0,0> ; 16-битный 64-килобайтный сегмент кода с базой RM_seg. 
    ;код (98h) - исполняемый сегмент, к которому запрещено обращение с целью записи и чтения.
    gdt_code32 descr <pm_seg_size-1, 0, 0, 98h, 0CFh, 0> ; определяет область в памяти, в которой хранятся коды инструкций
    gdt_data32 descr <pm_seg_size-1, 0, 0, 92h, 0CFh, 0> ; для объявления области памяти, где хранятся элементы данных для программы.
    gdt_stack32 descr <stack_size-1, 0, 0, 92h, 0CFh, 0> ; содержит значения данных, передаваемые в функции и процедуры в программе
	; Размер видеостраницы составляет 4000 байт - поэтому граница 3999.
    ; B8000h - базовый физический адрес страницы ( 8000h и 0Bh). 
    ; (Видео память размещена в первом Мегабайте адр. пр-ва поэтому base_m = 0).
	; линия А20 (20-ая адресная линия) создана для обратной совместимости процессоров Intel. Если её не открыть, то 20-ый бит будет нулём
    gdt_size=$-gdt

    gdtr dw gdt_size-1 ; размер нашей таблицы GDT+1байт (на саму метку)
         dd ? ; переменная размера 6 байт

    ; Селекторы сегментов кратность 8
    sel_data        equ 8
    sel_code16      equ 16
    sel_code32      equ 24
    sel_data32      equ 32
    sel_stack32     equ 40

; Обработчики 0..16 зарезервированы под прерывания и исключения системы; 17..31 - под "будущие поколения процессоров"; остальные могут быть использованы пользователем. Таким образом, обработчики для аппаратных прерываний должны начинаться минимум с 32-го.
;Ловушка — прерывание или исключение, при возникновении которого в стек записываются значения регистров cs: ip, указывающие на команду, следующую за командой, вызвавшей данное прерывание.

    ; таблица дескрипторов прерываний IDT -  Адресация прерываний.
    idt label byte
    ; первые 32 элемента таблицы (в программе не используются)
	;смещение в сегменте, нижняя часть; селектор сегмента с кодом прерывания;счётчик, не используется в программе;атрибуты ;смещение в сегменте, верхняя часть
	; описание по порядку: первые 12, потом 13-ая, затем остальные
    trap1     intr 13 dup (<0, sel_code32, 0, 8Fh, 0>)
    trap13    intr <0, sel_code32, 0, 8Fh, 0> ; Некоторые исключения кладут в стек код ошибки. В заглушке для 13 прерывания снимается со стека код ошибки.
    trap2     intr 18 dup (<0, sel_code32, 0, 8Fh, 0>)
    ; дескриптор прерывания от таймера. Вызывается после поступления сигнала от системного таймера на ножку IRQ0 ведущего контроллера прерываний
    int_time  intr <0, sel_code32, 0, 8Eh, 0>
    ; дескриптор прерывания от клавиатуры. Вызывается при нажатии на кнопку клавиатуры и при ее отжатии при поступлении сигнала на IRQ1 ведущего контроллера прерываний
    int_keyboard intr <0, sel_code32, 0, 8Eh, 0>
    
    idt_size=$-idt
    ; содержимое регистра IDTR в реальном режиме
    idtr            dw idt_size-1
                    dd ?

    rm_idtr         dw 3FFh,0,0

    hex             db 'h'
    hex_len=$-hex
    mb              db 'MB'
    mb_len=$-mb

    realm_msg db 'Now DOS in real mode.'
    to_pm_msg    db 'DOS switched to protected mode.'
    to_pm_msg_len=$-to_pm_msg
    timer_msg    db 'Timer ticks:   '
    timer_msg_len=$-timer_msg
    memory_msg    db 'Available memory: '
    memory_msg_len=$-memory_msg
    esc_from_pr  db 'To change to real mode press ESC'
    esc_from_pr_len=$-esc_from_pr
    ret_to_rm_msg   db 'DOS switched to real mode.'

    to_ascii    db 0, 1Bh, '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', '-', '=', 8
                db ' ', 'q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p', '[', ']', '$'
                db ' ', 'a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l', ';', '""', 0
                db 'z', 'x', 'c', 'v', 'b', 'n', 'm', ', ', '.', '/', 0, 0, 0, ' ', 0, 0
                db 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    
    attr1       db 1Fh
    attr2       db 3Fh
    screen_addr dd 640
    timer       dd 0

    master    db 0
    slave     db 0

; Макрос вывода строки в видеобуфер
print_str macro msg,len,offset
local print
    push   ebp
    mov    ecx,len
    mov    ebp,0B8000h
    add    ebp,offset
    xor    esi,esi
    mov    ah,attr2
print:
    mov    al,byte ptr msg[esi]
    mov    es:[ebp],ax
    add    ebp,2
    inc    esi
    loop   print
    pop    ebp
endm

; Макрос отправки сигнал EOI контроллеру прерываний
send_eoi macro
    mov    al,20h
    out    20h,al
endm

pm_start:
    ; Установить сегменты защищенного режима
    mov    ax,sel_data
    mov    ds,ax
    mov    es,ax
    mov    ax,sel_stack32
    mov    ebx,stack_size
    mov    ss,ax
    mov    esp,ebx

    ; Разрешить маскируемые прерывания
    sti

    ; Вывести справочную информацию в видеобуфер
    print_str to_pm_msg,to_pm_msg_len,380
    print_str timer_msg,timer_msg_len,540
    print_str memory_msg,memory_msg_len,5*160+60
    print_str esc_from_pr,esc_from_pr_len,6*160+60

    call available_memory
    jmp    $

; Обработчик исключения общей защиты
exc13 proc
    pop    eax
    iret
exc13 endp

; Обработчик остальных исключений
dummy_exc proc
    iret
dummy_exc endp

; Обработчик прерывания от системного таймера
int_time_handler:
    push   eax
    push   ebp
    push   ecx
    push   dx

    ; Загрузить счетчик
    mov    eax,timer

    ; Вывести счетчик в видеобуфер
    mov    ebp,0B8000h
    mov    ecx,8
    add    ebp,550+2*(timer_msg_len)
    mov    dh,attr2
main_loop:
    mov    dl,al
    and    dl,0Fh
    cmp    dl,10
    jl     less_than_10
    sub    dl,10
    add    dl,'A'
    jmp    print
less_than_10:
    add    dl,'0'
print:
    mov    es:[ebp],dx
    ror    eax,4
    sub    ebp,2
    loop   main_loop

    ; Инкрементировать и сохранить счетчик
    inc    eax
    mov    timer,eax

    send_eoi
    pop    dx
    pop    ecx
    pop    ebp
    pop    eax

    iretd

; Обработчик прерывания от клавиатуры
int_keyboard_handler:
    push   eax
    push   ebx
    push   es
    push   ds

    ; Получить из порта клавиатуры скан-код нажатой клавиши
    in     al,60h ; прочитать скан-код нажатой клавиши из порта клавиатуры

    ; Нажата клавиша ESC
    cmp    al,01h
    je     esc_pressed

    ; Нажата необслуживаемая клавиша
    cmp    al,39h
    ja     skip_translate

    ; Преобразовать скан-код в ASCII
    mov    bx,sel_data32
    mov    ds,bx
    mov    ebx,offset to_ascii
    xlatb
    mov    bx,sel_data
    mov    es,bx
    mov    ebx,screen_addr

    ; Нажата клавиша Backspace
    cmp    al,8
    je     backspace_pressed

    ; Вывести символ на экран
    mov    es:[ebx+0B8000h],al ; сейчас в EBP должно лежать положение первого символа на экране, с которого и будет распечатано число
    add    dword ptr screen_addr,2
    jmp    skip_translate

backspace_pressed:
    ; Удалить символ
    mov    al,' '
    sub    ebx,2 ; смещаемся на один символ влево (предыдущая цифра в ЕАХ)
    mov    es:[ebx+0B8000h],al ; возвращаем в EBP то же значение, что было в нём до пляски с видеопамятью
    mov    screen_addr,ebx

skip_translate:
    ; Разрешить работу клавиатуры
    in     al,61h
    or     al,80h
    out    61h,al

    send_eoi
    pop    ds
    pop    es
    pop    ebx
    pop    eax

    iretd

esc_pressed:
    ; Разрешить работу клавиатуры
    in     al,61h
    or     al,80h
    out    61h,al

    send_eoi
    pop    ds
    pop    es
    pop    ebx
    pop    eax

    ; Запретить маскируемые прерывания
    cli

    ; Вернуться в реальный режим
    db    0EAh
    dd    offset rm_return
    dw    sel_code16

; Процедура определения доступного объема оперативной памяти
available_memory proc
    push   ds

    mov    ax,sel_data ;кладем в него сегмент на 4 ГБ - все доступное виртуальное АП
    mov    ds,ax

    ; Пропустить первый мегабайт памяти
    mov    ebx,100001h ;пропускаем первый мегабайт оного сегмента
    ; Установить проверочный байт
    mov    dl,0FFh ;попытка считать значение из несуществующего байта памяти вернёт все нули (или все единицы - одно из двух, таких деталей автор не помнит)
				   ;в каждый байт мы пишем какое-то значение, а потом смотрим, что прочитается
    ; Установить максимальный объем оставшейся оперативной памяти
    mov    ecx,0FFEFFFFFh ;в ЕЦХ кладём количество оставшейся памяти (до превышения лимита в 4ГБ) - чтобы не было переполнения

check:
    ; Проверка сигнатуры
    mov    dh,ds:[ebx] ;сохраняем в DH текущее значение по некоторому байту памяти; EBX на первой итерации содержит смещение за 1й мегабайт памяти
							;мегабайт пропускаем потому, что в противном случае может произойти попытка редактирования процедуры собственного кода, что есть крайне не торт
    mov    ds:[ebx],dl ;кладём некоторое значение (заданное выше DL) в этот байт
    cmp    ds:[ebx],dl ;проверяем - считается обратно то же ДЛ, или какая-то хрень
    jnz    end_of_memory ;если считается хрень - то мы достигли дна, а на дне лежит конец памяти, вываливаемся из цикла
    mov    ds:[ebx],dh ;если дна не достигли - кладём обратно сохранённое значение, чтобы не попортить лишнего
    inc    ebx
    loop   check ;проверяем следующий байт.... ну вы поняли, ждать придётся столько, сколько гигабайтов ОЗУ в машине
	        	 ;к счастью, в досбоксе обычно всего 16 МБ памяти, так что не очень-то и долго ждать
				 ;желающие ждать больше (меньше?) могут поменять эти 16 МБ в конфиге досбокса

end_of_memory:
    pop    ds ;мемориджоб подошёл к логическому концу, память кончилась - восстанавливаем регистры
    xor    edx,edx 
    mov    eax,ebx ;в EBX лежит количество посчитанной памяти в байтах; кладём его в EAX,

    ; Разделить на мегабайт
    mov    ebx,100000h ; делим на 1 Мб, чтобы получить результат в мегабайтах
    div    ebx

    push   ecx
    push   dx
    push   ebp

    ; Вывести объем памяти на экран
    mov    ebp,0B8000h
    mov    ecx,8
    add    ebp,5*160+2*(memory_msg_len+7)+60
    mov    dh,attr2
cycle:
    mov    dl,al
    and    dl,0Fh
    cmp    dl,10
    jl     number
    sub    dl,10
    add    dl,'A'
    jmp    print_m
number:
    add    dl,'0'
print_m:
    mov    es:[ebp],dx
    ror    eax,4

    sub    ebp,2
    loop   cycle
    sub    ebp,0B8000h

    pop    ebp ;восстанавливаем потраченное смещение EBP
    pop    dx
    pop    ecx
    ret
available_memory endp

    pm_seg_size=$-gdt
pm_seg ends


rm_seg segment para public 'code' use16 ; USE16 - используем нижние части регистров, АХ ВХ СХ; верхние биты E* в реальном режиме недоступны
    assume cs:rm_seg,ds:pm_seg,ss:s_seg

; Макрос очистки экрана
cls macro
    mov    ax,3
    int    10h
endm

; Макрос печати строки
print_str macro msg
    mov    ah,9
    mov    edx,offset msg
    int    21h
endm

rm_start:
    mov    ax,pm_seg
    mov    ds,ax

    cls

    mov    AX, 0B800h
    mov    ES, AX
    mov    DI, 220
    mov    cx, 21
    mov    ebx, offset realm_msg
    mov    ah, attr1
    mov    al, byte ptr [ebx]
screen0:
    stosw
		; Команда STOSW сохраняет регистр AX в ячейке памяти по адресу ES:DI.
		; После выполнения команды, регистр DI увеличивается на 2 (если флаг DF = 0)
    inc    bx
    mov    al, byte ptr [ebx]
    loop   screen0; LOOP Выполняется до тех пор, пока CX не обнулится 
	; (CX каждый раз уменьшается на 1, а в CX лежит длина строки).


    ; Вычислить базы для всех используемых дескрипторов сегментов
    ; Линейные (32-битовые) адреса определяются путем умножения значений
    ; сегментных адресов на 16.
    xor    eax,eax
    mov    ax,rm_seg
    shl    eax,4 ; сегменты объявлены как PARA, нужно сдвинуть на 4 бита для выравнивания по границе параграфа
    mov    word ptr gdt_code16+2,ax
    shr    eax,16 ; сдвигаем  вправо (т.к. к старшей половине мы не можем обратиться в 16-разр.-р.)
    mov    byte ptr gdt_code16+4,al
    mov    ax,pm_seg
    shl    eax,4
    push eax		; для вычисления адреса idt
    push eax		; для вычисления адреса gdt
    mov    word ptr gdt_code32+2,ax
    mov    word ptr gdt_stack32+2,ax
    mov    word ptr gdt_data32+2,ax
    shr    eax,16 ; сдвигаем  вправо (т.к. к старшей половине мы не можем обратиться в 16-разр.-р.)
    mov    byte ptr gdt_code32+4,al
    mov    byte ptr gdt_stack32+4,al
    mov    byte ptr gdt_data32+4,al

    ; вычислим линейный адрес GDT
    pop eax
    add	eax,offset GDT ; в eax будет полный линейный адрес GDT (адрес сегмента + смещение GDT относительно него)
    ; аттеншен - все адреса в защищённом режиме ВИРТУАЛЬНЫЕ
    ; LGDT (Load GDT) - загружает в регистр процессора GDTR (GDT Register)  (лежит лин. адр этой табл)
    ; (LGDT относится к типу привилегированных команд.)
    ; Вызываем ее в р-р.
    ; Это говорит нам о том, что в р-р нет никакой защиты.
    ; информацию о таблице глобольных дескрипторов 
    ; (лин. базовый адрес иаблицы и ее границу). (Размещается в 6-байтах.)
    mov	dword ptr gdtr + 2,eax	; кладём полный линейный адрес в младшие 4 байта переменной gdtr
    mov word ptr gdtr, gdt_size - 1; в старшие 2 байта заносим размер gdt, из-за определения gdt_size (через $) настоящий размер на 1 байт меньше

    ; Установить регистр GDTR
    lgdt   fword ptr gdtr

    ; Вычислить линейный адрес IDT
    pop    eax
    add    eax,offset idt
    mov    dword ptr idtr+2,eax
    mov    word ptr idtr,idt_size-1

    ; Заполнить смещения в дескрипторах прерываний
    mov    eax,offset dummy_exc ; прерывание таймера
    mov    trap1.offs_l,ax
    shr    eax,16
    mov    trap1.offs_h,ax
    mov    eax,offset exc13
    mov    trap13.offs_l,ax
    shr    eax,16
    mov    trap13.offs_h,ax
    mov    eax,offset dummy_exc
    mov    trap2.offs_l,ax
    shr    eax,16
    mov    trap2.offs_h,ax
    mov    eax,offset int_time_handler ; прерывание таймера
    mov    int_time.offs_l,ax
    shr    eax,16
    mov    int_time.offs_h,ax
    mov    eax,offset int_keyboard_handler ; прерывание клавиатуры
    mov    int_keyboard.offs_l,ax
    shr    eax,16
    mov    int_keyboard.offs_h,ax

    ;сохраним маски прерываний контроллеров
    in	al, 21h							;ведущего, 21h - "магическая константа" - номер шины, in на неё даст нам набор масок (флагов)
    mov	master, al						; сохраняем в переменной master (понадобится для возвращения в RM)
    in	al, 0A1h						;ведомого - аналогично, in даёт набор масок для ведомого
    mov	slave, al

    ; Перепрограммировать ведущий контроллер прерываний
    mov    dx,20h
    mov    al,11h
    out    dx,al
    inc    dx
    mov    al,20h
    out    dx,al
    mov    al,4
    out    dx,al
    mov    al,1
    out    dx, al

    ; Запретить все прерывания в ведущем контроллере, кроме IRQ0 и IRQ1
    mov    al,11111100b
    out    dx,al

    ; Запретить все прерывания в ведомом контроллере
    mov    dx,0A1h
    mov    al,0FFh
    out    dx,al

    ; Загрузить регистр IDTR
    lidt   fword ptr idtr

    ; Открыть линию А20
    mov    al,0D1h
    out    64h,al
    mov    al,0DFh
    out    60h,al

    ; Отключить маскируемые и немаскируемые прерывания
    cli
    in     al,70h
    or     al,80h
    out    70h,al

    ; Перейти в защищенный режим установкой соответствующего бита регистра CR0
    mov    eax,cr0
    or     al,1 ; Поднимаем бит, которые переведет процессор в з-р.
    mov    cr0,eax ; Вот тут переводим в з-р процессор.


    ; Теперь процессор работает в з-р.!!!!!!!!!!!

    ; Перейти в сегмент кода защищенного режима
    ; Для кажого из сегментных регистров имеется теневой регистр дескриптора,
    ; который имеет формат дескриптора. Тен. рег. не доступны программисту.
    ; Они автоматически загружаются процессором из таблицы дескрипторов
    ; Каждый раз, когда процессор инициализирует соответствующий сегментный регистр.
    ; В з-р прогаммист имеет дело с селекторами, т.е. номерами дескрипторов,
    ; А процессор с самими дескрипторами, хранящимися в теневых регистрах.
    ; (Лин адрес сегмента, который хранится в тен. рег. определяет область памяти,
    ; К которой обращается процессор при выполнении конкретной программы).
    
    ; Загружаем в CS:IP селектор:смещение точки continue. 
    ; Мы используем jmp (дальнего перехода), чтобы изменить содержимое CS:IP
    ; Т.к. нам недоступно прямое образение к регистру CS 
    ; (мы не можем загрузить туда селектор).
    db     66h
    db     0EAh ; Код команды far jmp.
    dd     offset pm_start ; Смещение
    ; Указатель на описание сегмента называется селектор. 
    ; Другими словами, селектор - это номер дескриптора из таблицы дескрипторов (+ table indicator + RPL - requested privelege level).
    ; СЕЛЕКТОР:
    ; XXXXXXXX XXXXX YZZ
    ; XXXXXXXX XXXXX - номер дескриптора сегмента в GDT
    ; Y - TI (table indicator)
    ; ZZ - RPL - requested privilege level

    ; Селектор сегмента команд. (Записываем селектор, т.к. в з-р)
    ; Вот тут устанавливаем 0-ой уровень привелегий.
    dw     sel_code32

rm_return:
    ; Перейти в реальный режим сбросом соответствующего бита регистра CR0
    mov    eax,cr0
    and    al,0FEh ; Сбрасываем бит защищенного режима.
    mov    cr0,eax ; Запишем в CRO значени, в котором сброшен бит з-р.

	; ПЕРЕШЛИ В р-р. !!!!!!!!!!!!!!!!!!!!!!!

	; Снова выполняем дальний переход, 
	; Чтобы загрузить в регистр CS вместо хранящегося там селектора
	; Обычный сегментный адрес регистра команд.

    ; Сбросить очередь и загрузить CS
    db     0EAh ; Код команды far jmp
    dw     $+4 ; Смещение 
    dw     rm_seg ; Сегмент

	; ТЕПЕРЬ ПРОЦЕССОР СНОВА РАБОТАЕТ В Р-Р.

	; После перехода в р-р необходимо загрузить
	; В используемые далее сегментные регистры 
	; соответствубщие сегментные адреса.

    ; Восстановить регистры для работы в реальном режиме
    mov    ax,pm_seg ;загружаем в сегментные регистры "нормальные" (реальные) смещения
    mov    ds,ax
    mov    es,ax
    mov    ax,s_seg
    mov    ss,ax
    mov    ax,stack_size 
    mov    sp,ax ; Указатель стека указывает на вершину стека.

    ; Инициализировать контроллер прерываний
    ;перепрограммируем ведущий контроллер обратно на вектор 8 - смещение, по которому вызываются стандартные обработчики прерываний в реалмоде
    mov    al,11h
    out    20h,al
    mov    al,8 ;отправка смещения
    out    21h,al
    mov    al,4
    out    21h,al
    mov    al,1
    out    21h,al

    ; Восстановить маски контроллеров прерываний
    mov    al,master
    out    21h,al
    mov    al,slave
    out    0A1h,al

    ; Загрузить таблицу дескрипторов прерываний реального режима
    lidt   fword ptr rm_idtr

    ; Закрыть линию А20
    mov    al,0D1h
    out    64h,al
    mov    al,0DDh
    out    60h,al

    ; Разрешить немаскируемые и маскируемые прерывания
    in     al,70h
    and    al,07FH
    out    70h,al
    sti

    mov    AX, 0B800h
    mov    ES, AX
    mov    DI, 7*160+60
    mov    cx, 26
    mov    ebx, offset ret_to_rm_msg
    mov    ah, attr1
    mov    al, byte ptr [ebx]
screen01:
    stosw
    inc    bx
    mov    al, byte ptr [ebx]
    loop   screen01

    mov    ah,4Ch
    int    21h
    rm_seg_size = $-rm_start
rm_seg ends

s_seg segment para stack 'stack'
    stack_start db 100h dup(?)
    stack_size=$-stack_start
s_seg ends
    end    rm_start