#include <stdio.h>
#include <stdlib.h>
#include <errno.h> 
#include <unistd.h> 
#include <limits.h>
#include <string.h>
#include <dirent.h>
#include <sys/types.h>
#include <sys/stat.h>

#define FTW_F 1 // файл, не являющийся каталогом
#define FTW_D 2 // каталог
#define FTW_DNR 3 // каталог, который не может быть считан
#define FTW_NS 4 // ошибка в элементе, который не является символьной ссылкой

// Тип функции, которая будет вызываться для каждого встреченного файла
typedef int Handler(const char*, const struct stat*, int);

static Handler counter;
static int dopath(const char *filename, int depth, Handler*);

// обычные файлы, каталоги, блочные устройства, символьные устройства, именованные каналы, символические ссылки, сокеты, сумма
static long nreg, ndir, nblk, nchr, nfifo, nslink, nsock, nTotal;

// Обход дерева каталогов
static int dopath(const char *filename, int depth, Handler *func){
	struct stat statbuf; //получает сведения о файле или каталоге, указанные по пути, и сохраняет их в структуре, на которую указывает buffer.
	struct dirent *dirp;
	DIR *dp; // поток каталога.
	int rc = 0;
	
	// lstat возвращает информацию о файле в буфер    
	if (lstat(filename, &statbuf) < 0) // ошибка lstat -> выход из рекурсии
		return func(filename, &statbuf, FTW_NS);

	for (int i = 0; i < depth; ++i)
		printf("|\t");

	if (S_ISDIR(statbuf.st_mode) == 0) // Файл не каталог -> выход из рекурсии
		return func(filename, &statbuf, FTW_F); // отобразить в дереве

	if ((rc = func(filename, &statbuf, FTW_D)) != 0)
		return rc;

	// opendir открывает поток каталога и возвращает указатель на структуру типа DIR, которая содержит информацию о каталоге. 
	if (!(dp = opendir(filename))) // каталог недоступен -> выход из рекурсии
		return func(filename, &statbuf, FTW_DNR);

	chdir(filename); // устанавливает текущий каталог
	while ((dirp = readdir(dp)) && rc == 0) // readdir() возвращает название следующего файла в каталоге
		if (strcmp(dirp->d_name, ".") != 0 && strcmp(dirp->d_name, "..") != 0) // для того чтобы не обрабатывать свой и родительский каталоги
			rc = dopath(dirp->d_name, depth + 1, func);

	chdir("..");

	if (closedir(dp) < 0)
		perror("Невозможно закрыть каталог");

	return rc;
}

static int counter(const char *pathame, const struct stat *statptr, int type)
{
	switch (type)
	{
		case FTW_F: // файл не является каталогом
			printf("-- %s, %ld\n", pathame, statptr->st_ino);
			// stat возвращает информацию о файле filename и заполняет буфер buf. 
			switch (statptr->st_mode & S_IFMT)
			{
				case S_IFREG: // обычный файл
					nreg++;
					break;
				case S_IFBLK: // блочное устройство
					nblk++;
					break;
				case S_IFCHR: // символьное устройство
					nchr++;
					break;
				case S_IFIFO: // именованный канал
					nfifo++;
					break;
				case S_IFLNK: // символьная ссылка
					nslink++;
					break;
				case S_IFSOCK: // сокет
					nsock++;
					break;
				case S_IFDIR: // каталог
					perror("Католог имеет тип FTW_F");
					return -1;
			}
			break;
		case FTW_D: // каталог
			printf("-- %s/\n", pathame);
			ndir++;
			break;
		case FTW_DNR: // каталог, который не может быть считан
			perror("К одному из каталогов закрыт доступ.");
			return -1;
		case FTW_NS: // ошибка в элементе, который не является символьной ссылкой
			perror("Ошибка функции stat.");
			return -1;
		default:
			perror("Неизвестый тип файла.");
			return -1;
	}
	return 0;
}

int main(int argc, char *argv[])
{
	int rc = -1;
	rc = dopath(argv[1], 0, counter); //выполняет всю работу

	nTotal = nreg + ndir + nblk + nchr + nfifo + nslink + nsock;

	if (nTotal == 0)
		nTotal = 1; // во избежание деления на 0

	printf("Обычных файлов:\t\t%7ld, %5.2f%%\n", nreg, nreg * 100.0 / nTotal);
	printf("Каталогов:\t\t%7ld, %5.2f%%\n", ndir, ndir * 100.0 / nTotal);
	printf("Блочных устройств:\t%7ld, %5.2f%%\n", nblk, nblk * 100.0 / nTotal);
	printf("Символьных устройств:\t%7ld, %5.2f%%\n", nchr, nchr * 100.0 / nTotal);
	printf("Именованных каналов:\t%7ld, %5.2f%%\n", nfifo, nfifo * 100.0 / nTotal);
	printf("Символичеких ссылок:\t%7ld, %5.2f%%\n", nslink, nslink * 100.0 / nTotal);
	printf("Сокетов:\t\t%7ld, %5.2f%%\n", nsock, nsock * 100.0 / nTotal);
	printf("Всего:\t\t\t%7ld\n", nTotal);

	exit(rc);
}
