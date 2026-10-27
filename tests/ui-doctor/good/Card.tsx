export function Card({ user, onOpen, ...rest }: Props) {
  return (
    <article className="card" {...rest}>
      <img src={user.avatar} alt={`${user.name}'s avatar`} width={48} height={48} />
      <img {...user.cover} />
      <button type="button" onClick={() => onOpen(user.id)} aria-label="Close"><CloseIcon aria-hidden="true" /></button>
      <button type="button" onClick={() => onOpen(user.id)}>{user.cta}</button>
      <label htmlFor="name">Name</label>
      <input id="name" value={user.name} onChange={(e) => user.rename(e.target.value)} />
      <label>Search <input type="search" /></label>
      <a href={user.url} title="Profile"><Avatar /></a>
    </article>
  );
}
