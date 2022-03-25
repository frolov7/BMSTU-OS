#include <stdio.h>
#include <stdbool.h>
#include <windows.h>
#define WRITERS_N 3
#define READERS_N 5
#define N 3
#define SLEEP_TIME 2000 

HANDLE mutex; 
HANDLE can_write;
HANDLE can_read	;
HANDLE writers[WRITERS_N];
HANDLE readers[READERS_N];

volatile LONG active_readers_n = 0;
bool writing = false;
int value = 0;

volatile LONG waiting_writers_n = 0;
volatile LONG waiting_readers_n = 0;

void start_read(void) 
{
	//новый процесс читатель сможет начать работать, если нет
	//процесса писателя, изменяющего данные, в которых заинтересован читатель, и нет
	//писателей, ждущих свою очередь
	WaitForSingleObject(mutex, INFINITE);

	InterlockedIncrement(&waiting_readers_n); 
	if (writing || waiting_writers_n > 0) // если есть писатели либо он ожидает (бесконечное откладывание процессов писателей)
		WaitForSingleObject(can_read, INFINITE); // то ждем

	InterlockedDecrement(&waiting_readers_n);
	InterlockedIncrement(&active_readers_n);
	SetEvent(can_read); // можем читать
	ReleaseMutex(mutex); // освобождение объекта
}

void stop_read(void) 
{
	InterlockedDecrement(&active_readers_n);

	if (active_readers_n == 0)// если 0
	{ 
		ResetEvent(can_read);
		SetEvent(can_write); // можем писать
	}
}

void start_write(void) 
{
	InterlockedIncrement(&waiting_writers_n);
	// Писатель может начать свою работу, когда условие can_write станет равно истине
	if (writing || active_readers_n > 0) // если есть писатели либо кто то читает
		WaitForSingleObject(can_write, INFINITE); // то ждем
	// предпочтение отдается читателям если есть ожидающие иначе can_write
	InterlockedDecrement(&waiting_writers_n);
	writing = true;
}

void stop_write(void) 
{
	writing = false;

	if (waiting_readers_n > 0) // если есть ожидающие читатели
		SetEvent(can_read); // то разрешаем читать
	else 
		SetEvent(can_write); // пишем	
}

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wpointer-to-int-cast"

DWORD WINAPI writer(LPVOID lpParams) 
{
	// Писатель может начать свою работу, когда условие can_write станет равно истине
	for (int i = 0; i < N; ++i) 
	{
		start_write();

		++value;
		printf("Writer #%d write value %d\n", (int) lpParams, value);

		stop_write();
		Sleep(SLEEP_TIME);
	}

	return EXIT_SUCCESS;
}

DWORD WINAPI reader(LPVOID lpParams) 
{
	while (value < WRITERS_N * N) 
	{
		start_read();

		printf("Reader #%d read value %d\n", (int) lpParams, value);

		stop_read();
		Sleep(SLEEP_TIME);
	}
	// Если читатель заканчивает читать, то он вызывает процедуру stop_read
	return EXIT_SUCCESS;
}

#pragma GCC diagnostic pop

int init_handles(void) 
{
	// Создается Mutex, атрибут безопастности - флаг начального владельца - имя объекта
	if ((mutex = CreateMutex(NULL, FALSE, NULL)) == NULL) 
	{
		perror("CreateMutex");
		return EXIT_FAILURE;
	}
	// Создается объект событие (атрибут защиты, тип сброса, начальное состояние, имя обьекта)
	if ((can_read = CreateEvent(NULL, FALSE, TRUE, NULL)) == NULL) 
	{
		perror("CreateEvent");
		return EXIT_FAILURE;
	}

	if ((can_write = CreateEvent(NULL, FALSE, TRUE, NULL)) == NULL) 
	{
		perror("CreateEvent");
		return EXIT_FAILURE;
	}

	return EXIT_SUCCESS;
}


#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wint-to-pointer-cast"

int create_threads(HANDLE *threads, int threads_count, DWORD (*on_thread)(LPVOID)) 
{
	for (int i = 0; i < threads_count; ++i) 
	{
		if ((threads[i] = CreateThread(NULL, 0, on_thread, (LPVOID) i, 0, NULL)) == NULL) 
		{
			perror("CreateThread");
			return EXIT_FAILURE;
		}
	}

	return EXIT_SUCCESS;
}

#pragma GCC diagnostic pop

int main(void) 
{
	setbuf(stdout, NULL);

	int rc = EXIT_SUCCESS;

	if ((rc = init_handles()) != EXIT_SUCCESS || (rc = create_threads(writers, WRITERS_N, writer)) != EXIT_SUCCESS || (rc = create_threads(readers, READERS_N, reader)) != EXIT_SUCCESS)
		return rc;

	// приостанавливает поток пока все объекты не перейдут в сигнальное состояние
	WaitForMultipleObjects(WRITERS_N, writers, TRUE, INFINITE);  
	WaitForMultipleObjects(READERS_N, readers, TRUE, INFINITE); 

	CloseHandle(mutex); // закрывает дескриптор открытого объекта
	CloseHandle(can_read);
	CloseHandle(can_write);

	return rc;
}